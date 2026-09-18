extends Node3D
## Reuse Dante's actual articulated meshes and current wardrobe, including the
## canonical head. No replacement NPC head, and no reparenting the live actor.
const HELMET = preload("res://scripts/player/DanteHelmetVisual.gd")
var head_node: Node3D
var torso_node: Node3D
var source_head_id := 0
var arms: Array[Dictionary] = []
var legs: Array[Dictionary] = []
var arm_solver := preload("res://characters/PlayerCombatPose.gd").new()

func setup(actor: CharacterBody2D) -> void:
	for child in get_children(): child.free()
	arms.clear()
	legs.clear()
	source_head_id = actor.head_node.get_instance_id()
	scale = Vector3.ONE*1.2
	for key in ["torso_node","head_node","left_upper_arm","right_upper_arm","left_upper_leg","right_upper_leg"]:
		var source: Node3D = actor.get(key)
		var copy := source.duplicate() as Node3D
		add_child(copy)
		if key == "head_node": head_node = copy
		elif key == "torso_node": torso_node = copy
		elif "arm" in key:
			var side := -1.0 if key.begins_with("left") else 1.0
			var lower := copy.get_node("LeftLowerArm" if side < 0 else "RightLowerArm") as Node3D
			lower.position = Vector3(0,-.22,0)
			var weapon := lower.get_node_or_null("WeaponMount")
			if weapon: weapon.free()
			arms.append({"upper":copy,"lower":lower,"side":side})
		else:
			var side := -1.0 if key.begins_with("left") else 1.0
			var lower := copy.get_node("LeftLowerLeg" if side < 0 else "RightLowerLeg") as Node3D
			lower.position = Vector3(0,-.34,0)
			legs.append({"upper":copy,"lower":lower,"foot":lower.get_node("Foot"),"side":side})
	HELMET.attach(head_node)
	# Com o Dante Meshy, as cópias acima trazem as malhas antigas ocultas; o
	# modelo importado segue essas mesmas âncoras.
	if is_instance_valid(actor.get("meshy_rig")):
		var puppet := preload("res://scripts/player/MeshyDantePuppet.gd").new()
		add_child(puppet)
		puppet.configure(self, actor.current_outfit_id)

func pose(bike: Node3D, steering: float, foot_down: float, helmet_state: Node) -> void:
	var sport: bool = bike.style == "sport"
	var cruiser: bool = bike.style == "cruiser"
	var units := scale.x
	torso_node.position = Vector3(0,bike._seat_y+.21,.15 if sport or cruiser else .13)/units
	torso_node.rotation = Vector3(-.95 if sport else (-.10 if cruiser else -.22),0,0)
	# Same anchor contract as Dante's walking/sprinting rig, independent of yaw.
	head_node.position = torso_node.transform*Vector3(0,.36,0)
	head_node.rotation = Vector3(-.12 if sport else 0.0,0,0)
	var gesture := 0.0
	if helmet_state != null and helmet_state.action == "put_on":
		gesture = sin(PI*clampf(helmet_state.action_seconds/helmet_state.ACTION_SECONDS,0,1))
	for arm in arms:
		var side: float = arm.side
		arm.upper.position = torso_node.transform*Vector3(side*.185,.20,0)
		var axis: Vector3 = bike.get_meta("steering_axis_position")
		var grip := Vector3(side*.31,bike._handle_y+.015,bike._handle_z+.065)
		var target: Vector3 = (axis+Basis(Vector3.UP,steering)*(grip-axis))/units
		var shell := head_node.get_node("MotorcycleHelmet") as Node3D
		var touch := head_node.transform*(shell.position+Vector3(side*.16,-.06,0))
		target = target.lerp(touch,gesture)
		arm_solver._solve_arm(arm.upper,arm.lower,target,side)
	for leg in legs:
		var side: float = leg.side
		leg.upper.position = Vector3(side*.11,bike._seat_y+.025,.30 if sport else .18)/units
		var foot := Vector3(side*.26,.43,-.12 if cruiser else .14)
		if side < 0: foot = foot.lerp(Vector3(-.30,.065,.22),foot_down)
		_solve_leg(leg,foot/units)
	if helmet_state != null:
		HELMET.apply(head_node,helmet_state.worn,helmet_state.action,helmet_state.action_seconds/helmet_state.ACTION_SECONDS)

func _solve_leg(leg: Dictionary, target: Vector3) -> void:
	var upper: Node3D = leg.upper
	var lower: Node3D = leg.lower
	var delta := target-upper.position
	var direction := delta.normalized()
	var reach := clampf(delta.length(),.05,.639)
	var bend := Vector3(0,0,-1)
	bend = (bend-direction*bend.dot(direction)).normalized()
	var along := (.34*.34-.30*.30+reach*reach)/(2*reach)
	var knee := upper.position+direction*along+bend*sqrt(maxf(0,.34*.34-along*along))
	upper.quaternion = Quaternion(Vector3.DOWN,(knee-upper.position).normalized())
	lower.quaternion = Quaternion(Vector3.DOWN,upper.basis.inverse()*(upper.position+direction*reach-knee).normalized())
	leg.foot.basis = (upper.basis*lower.basis).inverse()
