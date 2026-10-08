extends SceneTree
## Retarget das mortes (Mixamo + `dying_backwards` do Dante) para o rig articulado de civis e policiais
## (`assets/CivilianModel.gd`: nós Pelvis → Spine → Head/braços e Pelvis → pernas, frente = +Z,
## membro pendurado em -Y). Saída: assets/dante/mixamo/npc_death.res, com death_left, death_right,
## death_forward e death_back. Cada trilha de rotação leva o nome da junta (usado por gameplay/MixamoDeath.gd).
##
## Tronco, cabeça e pernas seguem a rotação do osso (o repouso dos dois rigs coincide). Os braços
## seguem só a DIREÇÃO do osso: o repouso do Mixamo é em T e o do rig tem o braço pendurado, então
## copiar a rotação entortaria o braço. O quadril leva o deslocamento escalado pela altura do rig.
const OUT := "res://assets/dante/mixamo/npc_death.res"
const FPS := 30.0
const PELVIS_Y := 0.94
const LIE_LIFT := 0.07
const MIXAMO := {"Hips": "mixamorig_Hips", "Chest": "mixamorig_Spine2", "Head": "mixamorig_Head", "UpLeg": "mixamorig_%sUpLeg",
	"Leg": "mixamorig_%sLeg", "Foot": "mixamorig_%sFoot", "Arm": "mixamorig_%sArm", "ForeArm": "mixamorig_%sForeArm", "Hand": "mixamorig_%sHand"}
const DANTE := {"Hips": "Hips", "Chest": "Spine02", "Head": "Head", "UpLeg": "%sUpLeg", "Leg": "%sLeg", "Foot": "%sFoot",
	"Arm": "%sArm", "ForeArm": "%sForeArm", "Hand": "%sHand"}

func _sources() -> Array:
	return [
		{"clip": "death_left", "path": "res://assets/dante/mixamo/Standing React Death Left.fbx", "names": MIXAMO, "animation": ""},
		{"clip": "death_right", "path": "res://assets/dante/mixamo/Standing React Death Right.fbx", "names": MIXAMO, "animation": ""},
		{"clip": "death_forward", "path": "res://assets/dante/mixamo/Standing React Death Forward.fbx", "names": MIXAMO, "animation": ""},
		{"clip": "death_back", "path": "res://assets/dante.glb", "names": DANTE, "animation": "dying_backwards"},
	]

func _specs() -> Array:
	var specs := [
		{"name": "Pelvis", "kind": "full", "bone": "Hips", "parent": ""},
		{"name": "Spine", "kind": "full", "bone": "Chest", "parent": "Pelvis"},
		{"name": "Head", "kind": "full", "bone": "Head", "parent": "Spine"},
	]
	for side in ["left", "right"]:
		var title := "Left" if side == "left" else "Right"
		specs.append({"name": side + "_upper_leg", "kind": "full", "bone": "UpLeg", "side": side, "parent": "Pelvis"})
		specs.append({"name": side + "_lower_leg", "kind": "full", "bone": "Leg", "side": side, "parent": side + "_upper_leg"})
		specs.append({"name": title + "Foot", "kind": "full", "bone": "Foot", "side": side, "parent": side + "_lower_leg"})
		specs.append({"name": side + "_upper_arm", "kind": "aim", "bone": "Arm", "child": "ForeArm", "side": side, "parent": "Spine"})
		specs.append({"name": title + "Forearm", "kind": "aim", "bone": "ForeArm", "child": "Hand", "side": side, "parent": side + "_upper_arm"})
	return specs

func _init() -> void:
	var lib := AnimationLibrary.new()
	for source in _sources():
		var clip := _bake(source)
		lib.add_animation(source.clip, clip)
		print("CLIP ", source.clip, " len ", clip.length, " tracks ", clip.get_track_count())
	var err := ResourceSaver.save(lib, OUT)
	print("SAVED ", err, " clips ", lib.get_animation_list().size())
	quit()

func _bone(ss: Skeleton3D, names: Dictionary, key: String, source_side: String) -> int:
	var pattern: String = names[key]
	return ss.find_bone(pattern % source_side if pattern.contains("%s") else pattern)

func _bake(source: Dictionary) -> Animation:
	var node: Node = (load(source.path) as PackedScene).instantiate()
	root.add_child(node)
	var ss := node.find_child("Skeleton3D", true, false) as Skeleton3D
	var ap := node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var anim_name: String = source.animation if source.animation != "" else ap.get_animation_list()[0]
	var a := ap.get_animation(anim_name)
	var names: Dictionary = source.names
	# "left_*" do rig fica em X negativo; escolhe, no esqueleto de origem, o lado que também fica em X negativo.
	var left_bone := _bone(ss, names, "UpLeg", "Left")
	var negative_side := "Left" if ss.get_bone_global_rest(left_bone).origin.x < 0.0 else "Right"
	var positive_side := "Right" if negative_side == "Left" else "Left"
	var hips := _bone(ss, names, "Hips", "")
	var ratio := PELVIS_Y / maxf(ss.get_bone_global_rest(hips).origin.y, 0.001)
	var specs := _specs()
	var out := Animation.new()
	out.length = a.length
	out.loop_mode = Animation.LOOP_NONE
	var tracks := {}
	for spec in specs:
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, NodePath(spec.name))
		tracks[spec.name] = t
	var tp := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(tp, NodePath("Pelvis"))
	var n := int(ceil(a.length * FPS))
	for f in n + 1:
		var time := minf(f / FPS, a.length)
		_pose_source(ss, a, time)
		var globals := {}
		for spec in specs:
			var side: String = negative_side if spec.get("side", "") == "left" else positive_side
			var bone := _bone(ss, names, spec.bone, side)
			var parent_basis: Basis = globals[spec.parent] if spec.parent != "" else Basis.IDENTITY
			var g: Basis
			if spec.kind == "full":
				g = (chain(ss, bone).basis * ss.get_bone_global_rest(bone).basis.inverse()).orthonormalized()
			else:
				var child := _bone(ss, names, spec.child, side)
				var direction := (chain(ss, child).origin - chain(ss, bone).origin).normalized()
				g = parent_basis * Basis(Quaternion(Vector3(0, -1, 0), parent_basis.inverse() * direction))
			globals[spec.name] = g
			out.rotation_track_insert_key(tracks[spec.name], time, (parent_basis.inverse() * g).get_rotation_quaternion())
		var shift := (chain(ss, hips).origin - ss.get_bone_global_rest(hips).origin) * ratio
		# O corpo deitado tem espessura: sem isto o centro da cabeça e do tronco fica no nível do chão.
		var lowered := clampf(-shift.y / PELVIS_Y, 0.0, 1.0)
		out.position_track_insert_key(tp, time, Vector3(0, PELVIS_Y + LIE_LIFT * lowered, 0) + Vector3(shift.x, shift.y, shift.z))
	node.free()
	return out

func _pose_source(ss: Skeleton3D, a: Animation, time: float) -> void:
	for i in ss.get_bone_count(): ss.set_bone_pose(i, ss.get_bone_rest(i))
	for t in a.get_track_count():
		var p := str(a.track_get_path(t))
		var bone := p.get_slice(":", p.get_slice_count(":") - 1)
		var bi := ss.find_bone(bone)
		if bi < 0: continue
		match a.track_get_type(t):
			Animation.TYPE_ROTATION_3D: ss.set_bone_pose_rotation(bi, a.rotation_track_interpolate(t, time))
			Animation.TYPE_POSITION_3D: ss.set_bone_pose_position(bi, a.position_track_interpolate(t, time))
			Animation.TYPE_SCALE_3D: ss.set_bone_pose_scale(bi, a.scale_track_interpolate(t, time))

## Pose global pela cadeia de pais: o cache de `get_bone_global_pose` fica velho fora do loop.
static func chain(sk: Skeleton3D, bone: int) -> Transform3D:
	var t := sk.get_bone_pose(bone)
	var p := sk.get_bone_parent(bone)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return t
