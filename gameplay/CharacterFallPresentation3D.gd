extends RefCounted
## Native 3D character fall and death presentation.
## Restores V1 anatomical fall animation: limb bracing, pitch rotation with bounce,
## directional yaw from impact/bullet, ground settling, and randomized pose variants.

static func apply_fall(actor: Node3D, visual: Node3D, impact := Vector3.ZERO) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(visual): return
	if actor.has_meta("street_pose_owned"): return
	
	var impact_flat := Vector3(impact.x, 0.0, impact.z)
	var yaw: float = visual.rotation.y
	# O `pitch` positivo em X tomba o `visual` para +Z, que é as COSTAS do boneco
	# (o modelo fica girado 180° dentro do visual): a queda é sempre de costas.
	# Então o corpo vira DE FRENTE para a origem do golpe (visual -Z contra o
	# impacto) e cai para longe dela. Antes virava de costas para o atirador e
	# tombava na direção dele.
	if impact_flat.length_squared() > 0.05:
		yaw = atan2(impact_flat.x, impact_flat.z)
	elif randf() > 0.5:
		yaw = visual.rotation.y + randf_range(-0.35, 0.35)
	
	var variant: int = randi_range(0, 3)
	var duration: float = [1.02, 1.10, 0.95, 1.05][variant]
	var brace_end: float = [0.32, 0.40, 0.28, 0.30][variant]
	var fall_start: float = [0.10, 0.14, 0.08, 0.10][variant]
	
	var initial_rot := visual.rotation
	var initial_pos := visual.position
	
	var joints: Array[Dictionary] = []
	_gather_joints(actor, visual, variant, joints)
	
	var tween := actor.create_tween()
	if tween == null: return
	
	tween.tween_method(func(progress: float):
		var fall: float = smoothstep(fall_start, 0.78, progress)
		var brace: float = smoothstep(0.0, brace_end, progress)
		var settle: float = smoothstep(0.55, 1.0, progress)
		var bounce: float = sin(clampf((progress - 0.78) / 0.22, 0.0, 1.0) * PI) * 0.055
		var pitch: float = fall * (PI * 0.5) - bounce
		var facing: float = lerp_angle(initial_rot.y, yaw, brace)
		
		visual.rotation = Vector3(pitch, facing, lerpf(initial_rot.z, 0.06, fall))
		var height: float = -0.08 * sin(progress * PI)
		var center := Basis(Vector3.UP, facing) * Vector3(0.0, lerpf(0.0, 0.22, fall) + height, -0.65 * visual.scale.y * sin(pitch))
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
## Como a queda é de costas, "frente" termina apontando para o céu. Os braços antigos
## (X de -0,65 a -1,05) eram braços esticados para a frente e o cadáver ficava com os
## braços para cima. Aqui os braços se abrem para os lados e para trás (chão) na queda
## e assentam ao longo do corpo, abertos, com o cotovelo pouco dobrado.
static func _vary_pose(key: String, pose: Vector3, resting: bool, variant: int) -> Vector3:
	var side: float = -1.0 if key.begins_with("left") else 1.0
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

static func _gather_joints(actor: Node3D, visual: Node3D, variant: int, joints: Array[Dictionary]) -> void:
	var poses := {
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
		"left_lower_arm": "left_forearm", "right_lower_arm": "right_forearm",
		"left_upper_leg": "left_leg", "right_upper_leg": "right_leg",
		"left_lower_leg": "left_knee", "right_lower_leg": "right_knee"
	}
	for key in poses:
		var joint: Node3D = actor.get(key) as Node3D
		if not is_instance_valid(joint): joint = visual.get(key) as Node3D
		if not is_instance_valid(joint): joint = visual.get(aliases.get(key, key)) as Node3D
		if not is_instance_valid(joint): joint = visual.find_child(key, true, false) as Node3D
		if is_instance_valid(joint):
			joints.append({
				"key": key, "node": joint, "initial": joint.rotation,
				"brace": _vary_pose(key, poses[key][0], false, variant),
				"rest": _vary_pose(key, poses[key][1], true, variant)
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
					"brace": _vary_pose(key, Vector3(-0.4, 0, side * 0.4), false, variant),
					"rest": _vary_pose(key, Vector3(0.12, 0, side * (0.5 if i % 2 else 0.12)), true, variant)
				})
