extends RefCounted
## Morte de policiais e civis com os clipes do Mixamo (`tools/retarget_death_to_npc.gd`), sobre o rig
## articulado de `assets/CivilianModel.gd`. O clipe é escolhido pelo lado do empurrão. Sem a biblioteca
## ou sem alguma junta, `play` devolve false e a queda procedural de `CharacterFallPresentation3D` roda.
const LIBRARY := "res://assets/dante/mixamo/npc_death.res"
const JOINTS := ["Pelvis", "Spine", "Head", "left_upper_leg", "left_lower_leg", "LeftFoot", "left_upper_arm", "LeftForearm",
	"right_upper_leg", "right_lower_leg", "RightFoot", "right_upper_arm", "RightForearm"]
## O corpo passa da pose atual para o clipe em vez de pular para ele.
const BLEND_IN := 0.15
static var _library: AnimationLibrary

static func library() -> AnimationLibrary:
	if _library == null and ResourceLoader.exists(LIBRARY): _library = load(LIBRARY) as AnimationLibrary
	return _library

## Empurrão no referencial do corpo (frente = +Z, esquerda do Dante = +X): cai para o lado do empurrão.
static func clip_for(local_push: Vector3) -> String:
	if absf(local_push.z) >= absf(local_push.x): return "death_forward" if local_push.z > 0.0 else "death_back"
	return "death_left" if local_push.x > 0.0 else "death_right"

static func joints_of(visual: Node3D) -> Dictionary:
	var result := {}
	for joint_name in JOINTS:
		var node := visual.find_child(joint_name, true, false) as Node3D
		if node == null: return {}
		result[joint_name] = node
	return result

static func play(actor: Node3D, visual: Node3D, impact: Vector3) -> bool:
	var lib := library()
	if lib == null or not is_instance_valid(actor) or not is_instance_valid(visual): return false
	# Só quem morreu: quem cai e levanta (atropelado, derrubado) recompõe a pelve pela queda antiga.
	if actor.get("is_player") == true or actor.get("dead") != true: return false
	var joints := joints_of(visual)
	if joints.is_empty(): return false
	var pelvis: Node3D = joints["Pelvis"]
	var frame := pelvis.get_parent() as Node3D
	if frame == null: return false
	var flat := Vector3(impact.x, 0.0, impact.z)
	if flat.length_squared() < 0.05 and actor is CharacterBody3D:
		flat = Vector3((actor as CharacterBody3D).velocity.x, 0.0, (actor as CharacterBody3D).velocity.z)
	var local := Vector3.ZERO
	if flat.length_squared() < 0.05:
		var options: Array[Vector3] = [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
		local = options[randi_range(0, 3)]
	else:
		local = frame.global_basis.orthonormalized().inverse() * flat.normalized()
	var clip_name := clip_for(local)
	if not lib.has_animation(clip_name): return false
	var clip := lib.get_animation(clip_name)
	var rotations := {}
	var position_track := -1
	for track in clip.get_track_count():
		if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D: rotations[String(clip.track_get_path(track))] = track
		elif clip.track_get_type(track) == Animation.TYPE_POSITION_3D: position_track = track
	var initial := {}
	for joint_name in joints: initial[joint_name] = (joints[joint_name] as Node3D).quaternion
	var initial_position := pelvis.position
	# O modelo do civil pára de se pôr em pose quando o dono morre; garante o mesmo para quem não tem dono.
	if frame.has_method("set_process"): frame.set_process(false)
	if visual.has_method("set_process"): visual.set_process(false)
	var tween := actor.create_tween()
	if tween == null: return false
	tween.tween_method(func(time: float):
		var blend := smoothstep(0.0, BLEND_IN, time)
		for joint_name in rotations:
			var node: Node3D = joints.get(joint_name)
			if not is_instance_valid(node): continue
			node.quaternion = (initial[joint_name] as Quaternion).slerp(clip.rotation_track_interpolate(rotations[joint_name], time), blend)
		if position_track >= 0 and is_instance_valid(pelvis):
			pelvis.position = initial_position.lerp(clip.position_track_interpolate(position_track, time), blend)
	, 0.0, clip.length, clip.length)
	actor.set_meta("mixamo_death_clip", clip_name)
	return true
