extends RefCounted
## Use the actual Dante rig and existing articulated civilian legs; never a proxy rider.
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
const MODEL := preload("res://activities/skate/SkateModel.gd")

static func feet(board) -> Array[Vector3]:
	# Sole contacts, not ankle joints: Dante's boots and civilian shoes have
	# different ankle heights. Feet point sideways across the narrow deck.
	var front := Vector3(0, MODEL.DECK_HEIGHT, -.19)
	var back := Vector3(0, MODEL.DECK_HEIGHT, .20)
	if board.pushing:
		var phase: float = board.push_phase
		# Approach, sole contact, backward push, then lift back onto the tail.
		if phase < .18: back = back.lerp(Vector3(.28, 0, -.20), smoothstep(0, .18, phase))
		elif phase < .65: back = Vector3(.28, 0, lerpf(-.20, .36, (phase - .18) / .47))
		else:
			var t := (phase - .65) / .35
			back = Vector3(.28, 0, .36).lerp(back, smoothstep(0, 1, t)) + Vector3.UP * sin(t * PI) * .14
	if board.airborne:
		var lift := .24 * sin(minf(board.air_time / .6, 1) * PI)
		front.y += lift
		back.y += lift
	return [front, back]

static func apply(actor, board) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(actor.visual): return
	actor.visual.position = Vector3.ZERO
	actor.visual.basis = board.global_basis * board.visual.basis * Basis(Vector3.UP, -PI * .5)
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
		model.spine.rotation = Vector3(.05, -.25, -board.lean * .5)
		for index in 2:
			model.upper_arms[index].rotation = Vector3(-.12, 0, -.45 if index == 0 else .45)
			model.forearms[index].rotation.x = -.25

static func restore(actor) -> void:
	if not is_instance_valid(actor): return
	actor.visual.position = Vector3.ZERO
	actor.visual.rotation.x = 0
	actor.visual.rotation.z = 0
	if not actor.is_player and actor.visual.get_child_count() > 0: actor.visual.get_child(0).set_process(true)
