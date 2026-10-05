extends RefCounted
## Use the actual Dante rig and existing articulated civilian legs; never a proxy rider.
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
const MODEL := preload("res://activities/skate/SkateModel.gd")
const RECOVERY_DURATION := 1.1

static func feet(board) -> Array[Vector3]:
	# Staggered stance, with both feet and the torso facing the nose.
	var front := Vector3(-.065, MODEL.DECK_HEIGHT, -.16)
	var back := Vector3(.065, MODEL.DECK_HEIGHT, .16)
	if board.pushing:
		var phase: float = board.push_phase
		var direction := -1.0 if board._throttle < 0 else 1.0
		# Approach, sole contact, backward push, then lift back onto the tail.
		if phase < .18: back = back.lerp(Vector3(.28, 0, -.20 * direction), smoothstep(0, .18, phase))
		elif phase < .65: back = Vector3(.28, 0, lerpf(-.20, .36, (phase - .18) / .47) * direction)
		else:
			var t := (phase - .65) / .35
			back = Vector3(.28, 0, .36 * direction).lerp(back, smoothstep(0, 1, t)) + Vector3.UP * sin(t * PI) * .14
	if board.airborne:
		var lift := .24 * sin(minf(board.air_time / .6, 1) * PI)
		front.y += lift
		back.y += lift
	return [front, back]

static func apply(actor, board) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(actor.visual): return
	actor.visual.position = Vector3.ZERO
	actor.visual.global_basis = board.global_basis * board.visual.basis
	var targets := feet(board)
	var push_weight := sin(clampf(board.push_phase / .18, 0, 1) * PI * .5) if board.pushing else 0.0
	if board.pushing and board.push_phase > .65: push_weight *= 1 - smoothstep(.65, 1, board.push_phase)
	var tuck := sin(minf(board.air_time / .6, 1) * PI) if board.airborne else 0.0
	if actor.is_player:
		actor._apply_pose(actor._idle_pose)
		if actor.hips >= 0:
			var hip: Vector3 = actor.skeleton.get_bone_pose_position(actor.hips)
			# Add board height, then flex the supporting knee for the push.
			# Never raise the pelvis beyond the authored leg reach.
			hip.y += (MODEL.DECK_HEIGHT - .06 - .15 * push_weight - .12 * tuck) / actor.skeleton.global_basis.get_scale().y
			actor.skeleton.set_bone_pose_position(actor.hips, hip)
		for index in 2:
			var side := "Left" if index == 0 else "Right"
			var ankle: Vector3 = targets[index]
			ankle.y += actor._idle_feet[side].y
			actor._solve_leg(side, board.visual.to_global(ankle))
		# Idle already has relaxed shoulders and bent elbows; modest balance
		# motion avoids rotating imported bone-local axes into an overhead pose.
		var chest: int = actor._combat_bones.get("Spine02", -1)
		if chest >= 0:
			var pose: Basis = actor.skeleton.get_bone_global_pose(chest).basis
			actor._set_combat_bone_rotation(chest, Basis(Vector3.FORWARD, -.09 * push_weight - .12 * tuck) * pose)
	else:
		var model = actor.visual.get_child(0)
		if model.get("pelvis") == null: return
		var height: float = model.scale.y
		var pelvis_position := Vector3(0, model.PELVIS_Y + (MODEL.DECK_HEIGHT - .06 - .28 * push_weight - .12 * tuck) / height, 0)
		var basis := Basis.IDENTITY
		model.pelvis.transform = Transform3D(basis, pelvis_position)
		for index in 2:
			var ankle: Vector3 = targets[index] + Vector3.UP * KIT.ANKLE_HEIGHT * height
			var target: Vector3 = model.to_local(board.visual.to_global(ankle))
			model._place_leg(index, basis, pelvis_position, target, 0)
		model.spine.rotation = Vector3(-.08 - .1 * push_weight, 0, -board.lean * .5)
		for index in 2:
			model.upper_arms[index].rotation = Vector3(-.12, 0, -.45 if index == 0 else .45)
			model.forearms[index].rotation.x = -.25

static func fall(actor, age: float, heading: float) -> void:
	# Brace, absorb the impact, then get up through a crouch. Physics remains
	# owned by the swept player capsule; no free-running animation tween.
	var impact := smoothstep(0, .45, age)
	var rise := smoothstep(.5, RECOVERY_DURATION, age)
	var weight := impact * (1 - rise)
	actor.visual.rotation = Vector3(-1.25 * weight, heading, .18 * weight)
	actor.visual.position = Vector3(0, .30 * weight, 0)
	var brace := smoothstep(0, .18, age) * (1 - rise)
	if not actor.is_player:
		var model = actor.visual.get_child(0)
		model.pelvis.position = Vector3(0, model.PELVIS_Y, 0)
		model.spine.rotation = Vector3(-.22 * weight, 0, 0)
		for side in 2:
			model.thighs[side].rotation = Vector3(-(.65 if side == 0 else .4) * weight, 0, 0)
			model.shins[side].rotation = Vector3((1.15 if side == 0 else .85) * weight, 0, 0)
			model.upper_arms[side].rotation = Vector3(-.9 * brace, 0, (-.3 if side == 0 else .3) * brace)
			model.forearms[side].rotation = Vector3(-.6 * brace, 0, 0)
		return
	actor._apply_pose(actor._idle_pose)
	for entry in [["Spine02", -.22 * weight], ["LeftUpLeg", -.65 * weight], ["RightUpLeg", -.40 * weight], ["LeftLeg", 1.15 * weight], ["RightLeg", .85 * weight], ["LeftArm", -.85 * brace], ["RightArm", -1.05 * brace], ["LeftForeArm", -.55 * brace], ["RightForeArm", -.70 * brace]]:
		var bone: int = actor._combat_bones.get(entry[0], -1)
		if bone < 0: continue
		var pose: Basis = actor.skeleton.get_bone_global_pose(bone).basis
		actor._set_combat_bone_rotation(bone, Basis(Vector3.RIGHT, float(entry[1])) * pose)

static func restore(actor) -> void:
	if not is_instance_valid(actor): return
	actor.visual.position = Vector3.ZERO
	actor.visual.rotation.x = 0
	actor.visual.rotation.z = 0
	if actor.is_player: actor._apply_pose(actor._idle_pose)
	if not actor.is_player and actor.visual.get_child_count() > 0: actor.visual.get_child(0).set_process(true)
