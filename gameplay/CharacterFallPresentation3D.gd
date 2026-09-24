extends RefCounted
## Apresentação 3D de ferimento e queda dos personagens.
## As articulações acompanham a direção do impacto sem virar a vítima para o atirador.

static func _property_node(owner: Object, property_name: String) -> Node3D:
	for entry in owner.get_property_list():
		if String(entry.name) == property_name: return owner.get(property_name) as Node3D
	return null

static func _cancel_hit(actor: Node3D) -> void:
	var previous: Variant = actor.get_meta("v2_hit_tween", null)
	if previous is Tween and previous.is_valid(): previous.kill()
	var base: Dictionary = actor.get_meta("v2_hit_base", {})
	var root: Node3D = base.get("root") as Node3D
	if is_instance_valid(root):
		root.rotation.x = float(base.get("root_x", root.rotation.x))
		root.rotation.z = float(base.get("root_z", root.rotation.z))
	var torso: Node3D = base.get("torso") as Node3D
	if is_instance_valid(torso): torso.rotation = base.get("torso_rotation", torso.rotation)
	var head: Node3D = base.get("head") as Node3D
	if is_instance_valid(head): head.rotation = base.get("head_rotation", head.rotation)
	if actor.has_meta("v2_hit_tween"): actor.remove_meta("v2_hit_tween")
	if actor.has_meta("v2_hit_base"): actor.remove_meta("v2_hit_base")

static func apply_hit(actor: Node3D, visual: Node3D, impact: Vector3, amount: float) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(visual): return
	_cancel_hit(actor)
	if visual.has_method("react_to_hit"):
		visual.call("react_to_hit", impact, amount)
		return
	var model: Node3D = visual.get_child(0) as Node3D if visual.get_child_count() > 0 else visual
	if is_instance_valid(model) and model.has_method("react_to_hit"):
		model.call("react_to_hit", impact, amount)
		return
	var flat := Vector3(impact.x, 0.0, impact.z).normalized()
	if flat.is_zero_approx(): flat = visual.global_basis.z.normalized()
	var local := visual.global_basis.orthonormalized().inverse() * flat
	var strength := clampf(amount / 30.0, 0.4, 1.0)
	var root_start := visual.rotation
	var root_offset := Vector3(local.z * 0.045, 0.0, -local.x * 0.045) * strength
	var torso: Node3D = _property_node(visual, "torso_node")
	if not is_instance_valid(torso): torso = visual.find_child("Spine", true, false) as Node3D
	var head: Node3D = _property_node(visual, "head_node")
	if not is_instance_valid(head): head = visual.find_child("Head", true, false) as Node3D
	var torso_start := torso.rotation if is_instance_valid(torso) else Vector3.ZERO
	var head_start := head.rotation if is_instance_valid(head) else Vector3.ZERO
	var torso_offset := Vector3(local.z * 0.19, 0.0, -local.x * 0.18) * strength
	var head_offset := Vector3(-local.z * 0.09, 0.0, local.x * 0.10) * strength
	var tween := actor.create_tween()
	actor.set_meta("v2_hit_tween", tween)
	actor.set_meta("v2_hit_base", {"root": visual, "root_x": root_start.x, "root_z": root_start.z,
		"torso": torso, "torso_rotation": torso_start, "head": head, "head_rotation": head_start})
	tween.tween_method(func(progress: float):
		var push := smoothstep(0.0, 0.20, progress) * (1.0 - smoothstep(0.20, 1.0, progress))
		var lag := smoothstep(0.07, 0.30, progress) * (1.0 - smoothstep(0.30, 1.0, progress))
		if is_instance_valid(visual): visual.rotation = root_start + root_offset * push
		if is_instance_valid(torso): torso.rotation = torso_start + torso_offset * push
		if is_instance_valid(head): head.rotation = head_start + head_offset * lag
	, 0.0, 1.0, 0.36)

static func apply_fall(actor: Node3D, visual: Node3D, impact := Vector3.ZERO) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(visual): return
	_cancel_hit(actor)
	var impact_flat := Vector3(impact.x, 0.0, impact.z)
	var motion := Vector3.ZERO
	if actor is CharacterBody3D:
		var body := actor as CharacterBody3D
		motion = Vector3(body.velocity.x, 0.0, body.velocity.z)
	if impact_flat.length_squared() < 0.05: impact_flat = motion
	if impact_flat.length_squared() < 0.05:
		var directions: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
		impact_flat = visual.global_basis * directions[randi_range(0, 3)]
	else:
		impact_flat = (impact_flat.normalized() + motion.limit_length(4.0) * 0.10).normalized()
	var local := visual.global_basis.orthonormalized().inverse() * impact_flat.normalized()
	var side_fall := absf(local.x) > absf(local.z) * 0.85
	var mode := "side" if side_fall else ("front" if local.z < 0.0 else "back")
	var pitch_target := 0.0 if side_fall else signf(local.z) * PI * 0.5
	var roll_target := -signf(local.x) * PI * 0.5 if side_fall else 0.0
	var fall_direction := Vector3(signf(local.x), 0.0, 0.0) if side_fall else Vector3(0.0, 0.0, signf(local.z))
	
	var variant: int = randi_range(0, 3)
	var duration: float = [1.02, 1.10, 0.95, 1.05][variant]
	var brace_end: float = [0.32, 0.40, 0.28, 0.30][variant]
	var fall_start: float = [0.10, 0.14, 0.08, 0.10][variant]
	
	var initial_rot := visual.rotation
	var initial_pos := visual.position
	
	var joints: Array[Dictionary] = []
	_gather_joints(actor, visual, variant, mode, joints)
	
	var tween := actor.create_tween()
	if tween == null: return
	
	tween.tween_method(func(progress: float):
		var fall: float = smoothstep(fall_start, 0.78, progress)
		var brace: float = smoothstep(0.0, brace_end, progress)
		var settle: float = smoothstep(0.55, 1.0, progress)
		var bounce: float = sin(clampf((progress - 0.78) / 0.22, 0.0, 1.0) * PI) * 0.055
		var pitch: float = lerpf(initial_rot.x, pitch_target, fall) - signf(pitch_target) * bounce
		var roll: float = lerpf(initial_rot.z, roll_target, fall) - signf(roll_target) * bounce
		var facing: float = initial_rot.y + clampf(local.x, -1.0, 1.0) * 0.12 * brace
		visual.rotation = Vector3(pitch, facing, roll)
		var height: float = -0.08 * sin(progress * PI)
		var reach := 0.58 * visual.scale.y * sin(fall * PI * 0.5)
		var center := Basis(Vector3.UP, facing) * Vector3(-fall_direction.x * reach, lerpf(0.0, 0.22, fall) + height - 0.10 * brace * (1.0 - fall), -fall_direction.z * reach)
		visual.position = initial_pos + center
		
		for pose in joints:
			var node: Node3D = pose.get("node")
			if is_instance_valid(node):
				var p_init: Vector3 = pose.initial
				var p_brace: Vector3 = pose.brace
				var p_rest: Vector3 = pose.rest
				node.rotation = p_init.lerp(p_brace, brace).lerp(p_rest, settle)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)

## Convenção das articulações (espaço do modelo, frente = +Z, membro pendurado em -Y):
## X negativo leva o membro para a FRENTE, X positivo para TRÁS; Z com o sinal do lado abre para fora.
## Na queda frontal os braços procuram apoio; na lateral o braço de baixo abre.
static func _vary_pose(key: String, pose: Vector3, resting: bool, variant: int, mode: String) -> Vector3:
	var side: float = -1.0 if key.begins_with("left") else 1.0
	if key == "Spine":
		return Vector3(-0.12 if mode == "front" else 0.10, 0.0, 0.0) if resting else Vector3(-0.26 if mode == "front" else 0.20, 0.0, 0.0)
	if key == "Head":
		return Vector3(0.10 if mode == "front" else -0.08, 0.0, 0.0) if resting else Vector3(0.23 if mode == "front" else -0.18, 0.0, 0.0)
	if mode == "front" and key.contains("arm"):
		return Vector3(-0.45 if resting else -0.90, 0.0, side * (0.52 if resting else 0.30)) if key.contains("upper") else Vector3(0.42 if resting else 0.65, 0.0, 0.0)
	if mode == "side" and key.contains("arm"):
		var open_side := (side < 0.0) == (variant % 2 == 0)
		return Vector3(0.20 if resting else 0.55, 0.0, side * (0.85 if open_side else 0.25)) if key.contains("upper") else Vector3(0.35, 0.0, 0.0)
	if key.contains("arm"):
		var upper := key.contains("upper")
		match variant:
			0: # abertos em cruz
				if upper: return Vector3(0.30 if resting else 0.55, 0.0, side * (1.05 if resting else 0.95))
				return Vector3(-0.15 if resting else -0.35, 0.0, 0.0)
			1: # junto ao corpo
				if upper: return Vector3(0.12 if resting else 0.45, 0.0, side * (0.28 if resting else 0.55))
				return Vector3(-0.25 if resting else -0.40, 0.0, 0.0)
			_: # assimétrico: um braço aberto, o outro junto ao corpo
				var open_side: bool = (side < 0) == (variant == 2)
				if upper: return Vector3((0.25 if resting else 0.5), 0.0, side * ((1.15 if resting else 0.9) if open_side else (0.3 if resting else 0.5)))
				return Vector3(-0.2 if resting else -0.4, 0.0, 0.0)
	elif variant != 0:
		# Joelho que dobra na queda e fica levemente erguido; X negativo na coxa = joelho para cima.
		var bent: bool = variant == 1 or ((side < 0) == (variant == 2))
		if key.contains("lower") or key.contains("knee"):
			return Vector3((0.55 if resting else 1.05) if bent else 0.10, 0.0, 0.0)
		return Vector3((-0.35 if resting else -0.55) if bent else 0.05, 0.0, side * 0.12)
	return pose

static func _gather_joints(actor: Node3D, visual: Node3D, variant: int, mode: String, joints: Array[Dictionary]) -> void:
	var poses := {
		"Spine": [Vector3.ZERO, Vector3.ZERO],
		"Head": [Vector3.ZERO, Vector3.ZERO],
		"left_upper_leg": [Vector3(-0.48, 0, -0.08), Vector3(-0.10, 0, -0.14)],
		"right_upper_leg": [Vector3(-0.32, 0, 0.08), Vector3(0.12, 0, 0.12)],
		"left_lower_leg": [Vector3(0.95, 0, 0), Vector3(0.30, 0, 0)],
		"right_lower_leg": [Vector3(0.75, 0, 0), Vector3(0.16, 0, 0)],
		"left_upper_arm": [Vector3(-0.65, 0, -0.50), Vector3(-0.22, 0, -0.48)],
		"right_upper_arm": [Vector3(-0.85, 0, 0.55), Vector3(-0.42, 0, 0.62)],
		"left_lower_arm": [Vector3(0.45, 0, 0), Vector3(0.32, 0, 0)],
		"right_lower_arm": [Vector3(0.55, 0, 0), Vector3(0.50, 0, 0)]
	}
	var aliases := {
		"left_upper_arm": "left_arm", "right_upper_arm": "right_arm",
		"left_lower_arm": "LeftForearm", "right_lower_arm": "RightForearm",
		"left_upper_leg": "left_leg", "right_upper_leg": "right_leg",
		"left_lower_leg": "left_knee", "right_lower_leg": "right_knee"
	}
	for key in poses:
		var joint: Node3D = actor.get(key) as Node3D
		if not is_instance_valid(joint): joint = visual.get(key) as Node3D
		if not is_instance_valid(joint): joint = visual.get(aliases.get(key, key)) as Node3D
		if not is_instance_valid(joint): joint = visual.find_child(key, true, false) as Node3D
		if not is_instance_valid(joint): joint = visual.find_child(aliases.get(key, key), true, false) as Node3D
		if is_instance_valid(joint):
			joints.append({
				"key": key, "node": joint, "initial": joint.rotation,
				"brace": _vary_pose(key, poses[key][0], false, variant, mode),
				"rest": _vary_pose(key, poses[key][1], true, variant, mode)
			})
	
	if joints.is_empty():
		var model: Node = visual.get_child(0) if visual.get_child_count() > 0 else visual
		var limbs_val: Variant = model.get("limbs") if is_instance_valid(model) else visual.get("limbs")
		if limbs_val is Array:
			var limbs: Array = limbs_val
			for i in limbs.size():
				var limb := limbs[i] as Node3D
				if not is_instance_valid(limb): continue
				var side: float = -1.0 if i < 2 else 1.0
				var key: String = ("left_" if side < 0 else "right_") + ("upper_arm" if i % 2 else "upper_leg")
				joints.append({
					"key": key, "node": limb, "initial": limb.rotation,
					"brace": _vary_pose(key, Vector3(-0.4, 0, side * 0.4), false, variant, mode),
					"rest": _vary_pose(key, Vector3(0.12, 0, side * (0.5 if i % 2 else 0.12)), true, variant, mode)
				})
