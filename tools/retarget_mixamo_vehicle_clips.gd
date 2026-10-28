extends SceneTree
## Retarget dos clipes de veículo e de levantar do chão (Mixamo, baixados em 28/10/2026) para o
## esqueleto do Dante e para o rig articulado de civis/policiais (`assets/CivilianModel.gd`).
##
## Dante: mesmo método de tools/retarget_mixamo_death_to_dante.gd (rotação em espaço do esqueleto
## aplicada ao repouso do Dante; só o quadril recebe posição, escalada pela altura do quadril).
## NPC: mesmo método de tools/retarget_death_to_npc.gd (tronco/pernas copiam a rotação, braços só a
## direção do osso, pelve com o deslocamento escalado).
##
## Saídas: assets/dante/mixamo/dante_mixamo_vehicle.res (biblioteca "mixveh" do Actor) e
## assets/dante/mixamo/npc_vehicle.res (VehicleMocap/BodyGetUp). Medidas de alinhamento (quadril,
## mãos, frente do corpo) vão para evidence/mocap-vehicle-20261028/clips.json.
const DANTE_SCENE := "res://assets/dante.glb"
const DANTE_OUT := "res://assets/dante/mixamo/dante_mixamo_vehicle.res"
const NPC_OUT := "res://assets/dante/mixamo/npc_vehicle.res"
const REPORT := "res://evidence/mocap-vehicle-20261028/clips.json"
const DIR := "res://assets/dante/mixamo/"
const FPS := 30.0
## Clipe -> arquivo. `npc` = também vai para o rig dos NPCs.
const SOURCES := {
	"getup_back": {"file": "Getting Up From Back.fbx", "npc": true},
	"getup_stomach": {"file": "Getting Up From Stomach.fbx", "npc": true},
	"getup_knocked": {"file": "Getting Up Knocked Down.fbx", "npc": true},
	"enter_car": {"file": "Entering Car.fbx", "npc": false},
	"exit_car": {"file": "Exiting Car.fbx", "npc": false},
	"driving": {"file": "Driving.fbx", "npc": false},
	"pull_from_seat": {"file": "Pull Pilot From Seat.fbx", "npc": false},
	"pulled_from_seat": {"file": "Pulled From Seat.fbx", "npc": true},
	# O par do roubo foi gravado com o banco virado para a DIREITA de quem puxa (cabine de piloto); na porta
	# esquerda do carro o banco fica à esquerda: espelhado (lado trocado e reflexo no plano YZ).
	"pull_from_seat_m": {"file": "Pull Pilot From Seat.fbx", "npc": false, "mirror": true},
	"pulled_from_seat_m": {"file": "Pulled From Seat.fbx", "npc": true, "mirror": true},
}
## Reflexo no plano YZ (x → −x) de uma rotação: S·R·S com S = diag(−1, 1, 1).
static func _mirror(basis: Basis) -> Basis:
	var q := basis.get_rotation_quaternion()
	return Basis(Quaternion(q.x, -q.y, -q.z, q.w))

static func _other(bone_name: String) -> String:
	if bone_name.contains("Left"): return bone_name.replace("Left", "Right")
	if bone_name.contains("Right"): return bone_name.replace("Right", "Left")
	return bone_name
const MAP := {
	"Hips": "mixamorig_Hips", "Spine": "mixamorig_Spine", "Spine01": "mixamorig_Spine1", "Spine02": "mixamorig_Spine2",
	"neck": "mixamorig_Neck", "Head": "mixamorig_Head",
	"LeftShoulder": "mixamorig_LeftShoulder", "LeftArm": "mixamorig_LeftArm", "LeftForeArm": "mixamorig_LeftForeArm", "LeftHand": "mixamorig_LeftHand",
	"RightShoulder": "mixamorig_RightShoulder", "RightArm": "mixamorig_RightArm", "RightForeArm": "mixamorig_RightForeArm", "RightHand": "mixamorig_RightHand",
	"LeftUpLeg": "mixamorig_LeftUpLeg", "LeftLeg": "mixamorig_LeftLeg", "LeftFoot": "mixamorig_LeftFoot", "LeftToeBase": "mixamorig_LeftToeBase",
	"RightUpLeg": "mixamorig_RightUpLeg", "RightLeg": "mixamorig_RightLeg", "RightFoot": "mixamorig_RightFoot", "RightToeBase": "mixamorig_RightToeBase",
}
## Rig do NPC (ver tools/retarget_death_to_npc.gd).
const NPC_PELVIS_Y := 0.94
const NPC_LIE_LIFT := 0.07
const NPC_BONES := {"Hips": "mixamorig_Hips", "Chest": "mixamorig_Spine2", "Head": "mixamorig_Head", "UpLeg": "mixamorig_%sUpLeg",
	"Leg": "mixamorig_%sLeg", "Foot": "mixamorig_%sFoot", "Arm": "mixamorig_%sArm", "ForeArm": "mixamorig_%sForeArm", "Hand": "mixamorig_%sHand"}

var _ds: Skeleton3D
var _report := {}
## O clipe em preparo é espelhado (ver SOURCES).
var _mirrored := false

## Rotação global do osso de origem desde o repouso; espelhado, lê o osso do outro lado e reflete.
func _delta(ss: Skeleton3D, bone_name: String) -> Basis:
	var si := ss.find_bone(_other(bone_name) if _mirrored else bone_name)
	var delta := (chain(ss, si).basis * ss.get_bone_global_rest(si).basis.inverse()).orthonormalized()
	return _mirror(delta) if _mirrored else delta

## Repouso do osso no esqueleto de origem, com o mesmo reflexo do clipe.
func _rest_point(ss: Skeleton3D, bone: int) -> Vector3:
	var p := ss.get_bone_global_rest(bone).origin
	return Vector3(-p.x, p.y, p.z) if _mirrored else p

## Ponto do esqueleto de origem (espelhado: lado trocado e x negado).
func _point(ss: Skeleton3D, bone_name: String) -> Vector3:
	var p := chain(ss, ss.find_bone(_other(bone_name) if _mirrored else bone_name)).origin
	return Vector3(-p.x, p.y, p.z) if _mirrored else p

func _init() -> void:
	var dst: Node = (load(DANTE_SCENE) as PackedScene).instantiate()
	root.add_child(dst)
	_ds = dst.find_child("Skeleton3D", true, false)
	var dap := dst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var base: Node = dap.get_node(dap.root_node)
	var skel_path := str(base.get_path_to(_ds))
	var dante_lib := AnimationLibrary.new()
	var npc_lib := AnimationLibrary.new()
	for clip_name in SOURCES:
		var source: Dictionary = SOURCES[clip_name]
		var src: Node = (load(DIR + str(source.file)) as PackedScene).instantiate()
		root.add_child(src)
		var ss: Skeleton3D = src.find_child("Skeleton3D", true, false)
		var sap := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var a: Animation = sap.get_animation(sap.get_animation_list()[0])
		_mirrored = bool(source.get("mirror", false))
		dante_lib.add_animation(clip_name, _bake_dante(ss, a, skel_path))
		if source.npc: npc_lib.add_animation(clip_name, _bake_npc(ss, a))
		_report[clip_name] = _measure(ss, a)
		print("CLIP ", clip_name, " len ", a.length)
		src.free()
	print("SAVED dante ", ResourceSaver.save(dante_lib, DANTE_OUT), " npc ", ResourceSaver.save(npc_lib, NPC_OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT.get_base_dir()))
	var file := FileAccess.open(REPORT, FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "  "))
	file.close()
	quit()

func _bake_dante(ss: Skeleton3D, a: Animation, skel_path: String) -> Animation:
	var d_hip := _ds.find_bone("Hips")
	var s_hip := ss.find_bone("mixamorig_Hips")
	var ratio := _ds.get_bone_global_rest(d_hip).origin.y / maxf(ss.get_bone_global_rest(s_hip).origin.y, 0.001)
	var out := Animation.new()
	out.length = a.length
	out.loop_mode = Animation.LOOP_NONE
	var tracks := {}
	for d_name in MAP:
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, NodePath("%s:%s" % [skel_path, d_name]))
		tracks[d_name] = t
	var tp := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(tp, NodePath("%s:Hips" % skel_path))
	var n := int(ceil(a.length * FPS))
	for f in n + 1:
		var time := minf(f / FPS, a.length)
		_pose_source(ss, a, time)
		var globals := {}
		for i in _ds.get_bone_count():
			var bn := _ds.get_bone_name(i)
			var parent := _ds.get_bone_parent(i)
			var pg: Basis = globals[parent] if parent >= 0 and globals.has(parent) else (_ds.get_bone_global_rest(parent).basis if parent >= 0 else Basis())
			var g: Basis
			if MAP.has(bn):
				g = (_delta(ss, MAP[bn]) * _ds.get_bone_global_rest(i).basis).orthonormalized()
				out.rotation_track_insert_key(tracks[bn], time, (pg.inverse() * g).get_rotation_quaternion())
			else:
				g = pg * _ds.get_bone_rest(i).basis
			globals[i] = g
		var hp := (_point(ss, "mixamorig_Hips") - _rest_point(ss, s_hip)) * ratio
		out.position_track_insert_key(tp, time, _ds.get_bone_rest(d_hip).origin + hp)
	return out

func _npc_specs() -> Array:
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

func _npc_bone(ss: Skeleton3D, key: String, side: String) -> int:
	var pattern: String = NPC_BONES[key]
	return ss.find_bone(pattern % side if pattern.contains("%s") else pattern)

func _bake_npc(ss: Skeleton3D, a: Animation) -> Animation:
	var left_bone := _npc_bone(ss, "UpLeg", "Left")
	var negative_side := "Left" if ss.get_bone_global_rest(left_bone).origin.x < 0.0 else "Right"
	var positive_side := "Right" if negative_side == "Left" else "Left"
	var hips := _npc_bone(ss, "Hips", "")
	var ratio := NPC_PELVIS_Y / maxf(ss.get_bone_global_rest(hips).origin.y, 0.001)
	var specs := _npc_specs()
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
			var bone := _npc_bone(ss, spec.bone, side)
			var parent_basis: Basis = globals[spec.parent] if spec.parent != "" else Basis.IDENTITY
			var g: Basis
			if spec.kind == "full":
				g = _delta(ss, ss.get_bone_name(bone))
			else:
				var child := _npc_bone(ss, spec.child, side)
				var direction := (_point(ss, ss.get_bone_name(child)) - _point(ss, ss.get_bone_name(bone))).normalized()
				g = parent_basis * Basis(Quaternion(Vector3(0, -1, 0), parent_basis.inverse() * direction))
			globals[spec.name] = g
			out.rotation_track_insert_key(tracks[spec.name], time, (parent_basis.inverse() * g).get_rotation_quaternion())
		var shift := (_point(ss, "mixamorig_Hips") - _rest_point(ss, hips)) * ratio
		# Corpo deitado tem espessura: sem isto o centro do tronco fica no nível do chão.
		var lowered := clampf(-shift.y / NPC_PELVIS_Y, 0.0, 1.0)
		out.position_track_insert_key(tp, time, Vector3(0, NPC_PELVIS_Y + NPC_LIE_LIFT * lowered, 0) + shift)
	return out

## Medidas no espaço do clipe, em metros do Dante (escala do quadril), a cada 0,1 s: quadril, cabeça,
## mãos, pés e a frente do quadril. Servem para alinhar banco, porta e chão no jogo.
func _measure(ss: Skeleton3D, a: Animation) -> Dictionary:
	var s_hip := ss.find_bone("mixamorig_Hips")
	var ratio := _ds.get_bone_global_rest(_ds.find_bone("Hips")).origin.y / maxf(ss.get_bone_global_rest(s_hip).origin.y, 0.001)
	var samples := []
	var time := 0.0
	while time <= a.length + 0.0001:
		_pose_source(ss, a, minf(time, a.length))
		var sample := {"t": snappedf(time, 0.01)}
		for key in ["Hips", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
			var p := _point(ss, "mixamorig_" + key) * ratio
			sample[key] = [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]
		var front: Vector3 = _delta(ss, "mixamorig_Hips") * Vector3(0, 0, 1)
		sample["front"] = [snappedf(front.x, 0.01), snappedf(front.y, 0.01), snappedf(front.z, 0.01)]
		samples.append(sample)
		time += 0.1
	return {"length": a.length, "ratio": ratio, "samples": samples}

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
