extends RefCounted
## Use the actual Dante rig and existing articulated civilian legs; never a proxy rider.
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
const MODEL := preload("res://activities/skate/SkateModel.gd")
const RECOVERY_DURATION := 1.1

static func feet(board) -> Array[Vector3]:
	# Staggered stance, with both feet and the torso facing the nose.
	# Both imported rigs face +Z and Actor rotates their model by PI. The
	# left hip is therefore on board +X; swapping these crossed both legs.
	var front := Vector3(.065, MODEL.DECK_HEIGHT, -.16)
	var back := Vector3(-.065, MODEL.DECK_HEIGHT, .16)
	if board.pushing:
		var phase: float = board.push_phase
		var direction: float = board.push_direction
		# Tests/previews may pose a board without a live contact probe.
		if not board.push_support: direction = -1.0 if board._throttle < 0 else 1.0
		var ground: Vector3 = board.push_foot if board.push_support else Vector3(-.28, 0, lerpf(-.20, .36, clampf((phase - .18) / .47, 0, 1)) * direction)
		# Approach, sole contact, backward push, then lift back onto the tail.
		if phase < .18: back = back.lerp(ground, smoothstep(0, .18, phase))
		elif phase < .65: back = ground
		else:
			var t := (phase - .65) / .35
			back = ground.lerp(back, smoothstep(0, 1, t)) + Vector3.UP * sin(t * PI) * .14
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
	var compression: float = board.landing_compression + board.terrain_flex + (.055 if actor.is_player else 0.0)
	if actor.is_player:
		actor._apply_pose(actor._idle_pose)
		if actor.hips >= 0:
			var hip: Vector3 = actor.skeleton.get_bone_pose_position(actor.hips)
			# Add board height, then flex the supporting knee for the push.
			# Never raise the pelvis beyond the authored leg reach.
			hip.y += (MODEL.DECK_HEIGHT - .06 - .15 * push_weight - .12 * tuck - compression) / actor.skeleton.global_basis.get_scale().y
			actor.skeleton.set_bone_pose_position(actor.hips, hip)
		var world_targets: Array[Vector3] = []
		var drop := 0.0
		for index in 2:
			var side := "Left" if index == 0 else "Right"
			var ankle: Vector3 = targets[index]
			ankle.y += actor._idle_feet[side].y
			var target: Vector3 = board.visual.to_global(ankle)
			if index == 1 and board.push_contact:
				target = board.visual.to_global(targets[index]) + board.push_normal * actor._idle_feet[side].y
			world_targets.append(target)
			var upper: int = actor._combat_bones[side + "UpLeg"]
			var lower: int = actor._combat_bones[side + "Leg"]
			var foot: int = actor._combat_bones[side + "Foot"]
			var reach: float = (actor._combat_rests[lower].origin.length() + actor._combat_rests[foot].origin.length()) * .995
			var gap: Vector3 = actor.skeleton.get_bone_global_pose(upper).origin - actor.skeleton.to_local(target)
			drop = maxf(drop, gap.y - sqrt(maxf(reach * reach - gap.x * gap.x - gap.z * gap.z, 0)))
		if actor.hips >= 0:
			var hip: Vector3 = actor.skeleton.get_bone_pose_position(actor.hips)
			hip.y -= drop
			actor.skeleton.set_bone_pose_position(actor.hips, hip)
		for index in 2: actor._solve_leg("Left" if index == 0 else "Right", world_targets[index])
		# Idle already has relaxed shoulders and bent elbows; modest balance
		# motion avoids rotating imported bone-local axes into an overhead pose.
		var chest: int = actor._combat_bones.get("Spine02", -1)
		if chest >= 0:
			var pose: Basis = actor.skeleton.get_bone_global_pose(chest).basis
			actor._set_combat_bone_rotation(chest, Basis(Vector3.FORWARD, board.lean * .5) * Basis(Vector3.UP, .28 * (1.0 - push_weight)) * Basis(Vector3.RIGHT, .10 + .12 * push_weight + .16 * tuck) * pose)
		var swing := sin(board.push_phase * TAU) * push_weight
		for index in 2:
			var side := "Left" if index == 0 else "Right"
			var sign_side := -1.0 if index == 0 else 1.0
			var arm: int = actor._combat_bones.get(side + "Arm", -1)
			if arm >= 0:
				var rest: Basis = actor.skeleton.get_bone_global_pose(arm).basis
				var balance := sign_side * (.13 + absf(board.lean) * .7 + tuck * .20)
				actor._set_combat_bone_rotation(arm, Basis(Vector3.FORWARD, balance) * Basis(Vector3.RIGHT, sign_side * swing * .26) * rest)
			var forearm: int = actor._combat_bones.get(side + "ForeArm", -1)
			if forearm >= 0:
				var rest: Basis = actor.skeleton.get_bone_global_pose(forearm).basis
				actor._set_combat_bone_rotation(forearm, Basis(Vector3.RIGHT, -.14 - push_weight * .14) * rest)
	else:
		var model = actor.visual.get_child(0)
		if model.get("pelvis") == null: return
		var height: float = model.scale.y
		var pelvis_position := Vector3(-.035 * push_weight, model.pelvis_y + (MODEL.DECK_HEIGHT - .08 - .24 * push_weight - .12 * tuck - compression) / height, 0)
		var basis := Basis.from_euler(Vector3(.03 * push_weight, -.4 * (1 - push_weight), board.lean * .3))
		# Respect authored leg lengths on uneven support beside the board.
		var ankles: Array[Vector3] = []
		var reach: float = (model.thigh_len + model.shin_len) * .995
		var drop := 0.0
		for index in 2:
			var ankle: Vector3 = targets[index] + Vector3.UP * model.ankle_height * height
			var world_ankle: Vector3 = board.visual.to_global(ankle)
			if index == 1 and board.push_contact:
				world_ankle = board.visual.to_global(targets[index]) + board.push_normal * model.ankle_height * height
			var target: Vector3 = model.to_local(world_ankle)
			ankles.append(target)
			var gap: Vector3 = pelvis_position + basis * model._hip_offsets[index] - target
			drop = maxf(drop, gap.y - sqrt(maxf(reach * reach - gap.x * gap.x - gap.z * gap.z, 0)))
		pelvis_position.y -= drop
		model.pelvis.transform = Transform3D(basis, pelvis_position)
		for index in 2:
			model._place_leg(index, basis, pelvis_position, ankles[index], 0)
			var sole_basis: Basis = board.visual.global_basis * Basis(Vector3.UP, (.65 if index == 0 else .9) * (1 - push_weight)) * Basis(Vector3.UP, PI)
			if index == 1 and board.push_contact:
				var toe: Vector3 = (-board.global_basis.z).slide(board.push_normal).normalized()
				sole_basis = Basis(-toe.cross(board.push_normal).normalized(), board.push_normal, toe)
			model.feet[index].global_basis = sole_basis * Basis.from_scale(Vector3.ONE * height)
		model.spine.rotation = Vector3(.07 + .12 * push_weight + .1 * tuck, .2 * (1 - push_weight), board.lean * .65)
		model.head_node.rotation = Vector3(-.04, .2 * (1 - push_weight), -board.lean * .25)
		var swing := sin(board.push_phase * TAU) * push_weight
		for index in 2:
			var side := -1.0 if index == 0 else 1.0
			model.upper_arms[index].rotation = Vector3(-.1 - side * swing * .22, 0, side * (.12 + absf(board.lean) * .4 + tuck * .18))
			model.forearms[index].rotation.x = -.3 - push_weight * (.12 if index == 0 else .25)

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
		model.pelvis.position = Vector3(0, model.pelvis_y, 0)
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
