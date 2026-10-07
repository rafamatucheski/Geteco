extends SceneTree
## Retarget das animações da Universal Animation Library (Quaternius, CC0) para o
## esqueleto do Dante. Rotação em espaço do esqueleto (delta da pose em relação ao
## repouso, aplicado ao repouso do Dante), porque os ossos dos dois rigs têm
## orientações de repouso diferentes e um mapeamento osso a osso em espaço local
## entorta braços e pernas. Só o quadril recebe posição, escalada pela razão de alturas.
const SRC := "res://assets/animation_library/AnimationLibrary_Godot_Standard.glb"
const DST := "res://assets/dante.glb"
const OUT := "res://assets/animation_library/dante_ual.res"
const FPS := 30.0
const MAP := {
	"Hips": "DEF-hips", "Spine": "DEF-spine.001", "Spine01": "DEF-spine.002", "Spine02": "DEF-spine.003",
	"neck": "DEF-neck", "Head": "DEF-head",
	"LeftShoulder": "DEF-shoulder.L", "LeftArm": "DEF-upper_arm.L", "LeftForeArm": "DEF-forearm.L", "LeftHand": "DEF-hand.L",
	"RightShoulder": "DEF-shoulder.R", "RightArm": "DEF-upper_arm.R", "RightForeArm": "DEF-forearm.R", "RightHand": "DEF-hand.R",
	"LeftUpLeg": "DEF-thigh.L", "LeftLeg": "DEF-shin.L", "LeftFoot": "DEF-foot.L", "LeftToeBase": "DEF-toe.L",
	"RightUpLeg": "DEF-thigh.R", "RightLeg": "DEF-shin.R", "RightFoot": "DEF-foot.R", "RightToeBase": "DEF-toe.R",
}

var _ss: Skeleton3D
var _ds: Skeleton3D

func _init() -> void:
	var src: Node = (load(SRC) as PackedScene).instantiate()
	var dst: Node = (load(DST) as PackedScene).instantiate()
	root.add_child(src); root.add_child(dst)
	_ss = src.find_child("Skeleton3D", true, false)
	_ds = dst.find_child("Skeleton3D", true, false)
	var sap := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var dap := dst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var base: Node = dap.get_node(dap.root_node)
	var skel_path := str(base.get_path_to(_ds))
	var s_hip := _ss.find_bone("DEF-hips"); var d_hip := _ds.find_bone("Hips")
	var ratio := _ds.get_bone_global_rest(d_hip).origin.y / maxf(_ss.get_bone_global_rest(s_hip).origin.y, 0.001)
	print("RATIO ", ratio, " skel_path ", skel_path)
	var lib := AnimationLibrary.new()
	var worst := 0.0
	for clip in sap.get_animation_list():
		if clip == "A_TPose" or clip == "RESET": continue
		var a: Animation = sap.get_animation(clip)
		var out := Animation.new()
		out.length = a.length
		out.loop_mode = a.loop_mode
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
			_pose_source(a, time)
			for i in _ds.get_bone_count(): _ds.set_bone_pose(i, _ds.get_bone_rest(i))
			var globals := {}
			for i in _ds.get_bone_count():
				var bn := _ds.get_bone_name(i)
				var parent := _ds.get_bone_parent(i)
				var pg: Basis = globals[parent] if parent >= 0 and globals.has(parent) else (_ds.get_bone_global_rest(parent).basis if parent >= 0 else Basis())
				var g: Basis
				if MAP.has(bn):
					var si := _ss.find_bone(MAP[bn])
					g = chain(_ss, si).basis * _ss.get_bone_global_rest(si).basis.inverse() * _ds.get_bone_global_rest(i).basis
					g = g.orthonormalized()
					var local := (pg.inverse() * g).get_rotation_quaternion()
					out.rotation_track_insert_key(tracks[bn], time, local)
				else:
					g = pg * _ds.get_bone_rest(i).basis
				globals[i] = g
			var hp := (chain(_ss, s_hip).origin - _ss.get_bone_global_rest(s_hip).origin) * ratio
			out.position_track_insert_key(tp, time, _ds.get_bone_rest(d_hip).origin + hp)
		lib.add_animation(clip, out)
	var err := ResourceSaver.save(lib, OUT)
	print("SAVED ", err, " clips ", lib.get_animation_list().size())
	quit()

func _pose_source(a: Animation, time: float) -> void:
	for i in _ss.get_bone_count(): _ss.set_bone_pose(i, _ss.get_bone_rest(i))
	for t in a.get_track_count():
		var p := str(a.track_get_path(t))
		var bone := p.get_slice(":", p.get_slice_count(":") - 1)
		var bi := _ss.find_bone(bone)
		if bi < 0: continue
		match a.track_get_type(t):
			Animation.TYPE_ROTATION_3D: _ss.set_bone_pose_rotation(bi, a.rotation_track_interpolate(t, time))
			Animation.TYPE_POSITION_3D: _ss.set_bone_pose_position(bi, a.position_track_interpolate(t, time))
			Animation.TYPE_SCALE_3D: _ss.set_bone_pose_scale(bi, a.scale_track_interpolate(t, time))

## Pose global calculada pela cadeia de pais: o cache de `get_bone_global_pose` fica
## velho fora do loop de processamento do esqueleto e devolvia sempre o repouso.
static func chain(sk: Skeleton3D, bone: int) -> Transform3D:
	var t := sk.get_bone_pose(bone)
	var p := sk.get_bone_parent(bone)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return t
