extends SceneTree
## Retarget das animações de espada do Mixamo (guardar, sacar e guardar a greatsword) para o Dante.
## Mesmo método de tools/retarget_ual_to_dante.gd: rotação em espaço do esqueleto aplicada ao
## repouso do Dante, porque os repousos dos dois rigs diferem. Só o quadril recebe posição.
## Saída: assets/dante/mixamo/dante_mixamo_death.res, com um clipe por direção.
const DST := "res://assets/dante.glb"
const OUT := "res://assets/dante/mixamo/dante_mixamo_sword.res"
const SOURCES := {
	"sheathe_katana": "res://assets/dante/mixamo/Sheathing Sword.fbx",
	"withdraw_katana": "res://assets/dante/mixamo/Withdrawing Sword.fbx",
	"sheathe_greatsword": "res://assets/dante/mixamo/Sheath A Great Sword 1.fbx",
	"gs_downward": "res://assets/dante/mixamo/Great Sword Downward Slash.fbx",
	"gs_power": "res://assets/dante/mixamo/Great Sword Power Slash.fbx",
	"gs_low": "res://assets/dante/mixamo/Great Sword Low Slash.fbx",
	"gs_combo": "res://assets/dante/mixamo/Great Sword Combo Slash.fbx",
	"gs_idle": "res://assets/dante/mixamo/Great Sword Idle.fbx",
	# Andar e correr da greatsword (baixados "In Place", sem pele, 30 fps): locomoção com a katana.
	"gs_walk": "res://assets/dante/mixamo/Great Sword Walk.fbx",
	"gs_run": "res://assets/dante/mixamo/Great Sword Run.fbx",
}
const FPS := 30.0
# Ossos do Dante -> ossos do Mixamo (o importador troca ':' por '_').
const MAP := {
	"Hips": "mixamorig_Hips", "Spine": "mixamorig_Spine", "Spine01": "mixamorig_Spine1", "Spine02": "mixamorig_Spine2",
	"neck": "mixamorig_Neck", "Head": "mixamorig_Head",
	"LeftShoulder": "mixamorig_LeftShoulder", "LeftArm": "mixamorig_LeftArm", "LeftForeArm": "mixamorig_LeftForeArm", "LeftHand": "mixamorig_LeftHand",
	"RightShoulder": "mixamorig_RightShoulder", "RightArm": "mixamorig_RightArm", "RightForeArm": "mixamorig_RightForeArm", "RightHand": "mixamorig_RightHand",
	"LeftUpLeg": "mixamorig_LeftUpLeg", "LeftLeg": "mixamorig_LeftLeg", "LeftFoot": "mixamorig_LeftFoot", "LeftToeBase": "mixamorig_LeftToeBase",
	"RightUpLeg": "mixamorig_RightUpLeg", "RightLeg": "mixamorig_RightLeg", "RightFoot": "mixamorig_RightFoot", "RightToeBase": "mixamorig_RightToeBase",
}

var _ds: Skeleton3D

func _init() -> void:
	var dst: Node = (load(DST) as PackedScene).instantiate()
	root.add_child(dst)
	_ds = dst.find_child("Skeleton3D", true, false)
	var dap := dst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var base: Node = dap.get_node(dap.root_node)
	var skel_path := str(base.get_path_to(_ds))
	var d_hip := _ds.find_bone("Hips")
	var lib := AnimationLibrary.new()
	for clip_name in SOURCES:
		var src: Node = (load(SOURCES[clip_name]) as PackedScene).instantiate()
		root.add_child(src)
		var ss: Skeleton3D = src.find_child("Skeleton3D", true, false)
		var sap := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var s_hip := ss.find_bone("mixamorig_Hips")
		var ratio := _ds.get_bone_global_rest(d_hip).origin.y / maxf(ss.get_bone_global_rest(s_hip).origin.y, 0.001)
		var a: Animation = sap.get_animation(sap.get_animation_list()[0])
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
			for i in _ds.get_bone_count(): _ds.set_bone_pose(i, _ds.get_bone_rest(i))
			var globals := {}
			for i in _ds.get_bone_count():
				var bn := _ds.get_bone_name(i)
				var parent := _ds.get_bone_parent(i)
				var pg: Basis = globals[parent] if parent >= 0 and globals.has(parent) else (_ds.get_bone_global_rest(parent).basis if parent >= 0 else Basis())
				var g: Basis
				if MAP.has(bn):
					var si := ss.find_bone(MAP[bn])
					g = chain(ss, si).basis * ss.get_bone_global_rest(si).basis.inverse() * _ds.get_bone_global_rest(i).basis
					g = g.orthonormalized()
					var local := (pg.inverse() * g).get_rotation_quaternion()
					out.rotation_track_insert_key(tracks[bn], time, local)
				else:
					g = pg * _ds.get_bone_rest(i).basis
				globals[i] = g
			var hp := (chain(ss, s_hip).origin - ss.get_bone_global_rest(s_hip).origin) * ratio
			out.position_track_insert_key(tp, time, _ds.get_bone_rest(d_hip).origin + hp)
		lib.add_animation(clip_name, out)
		print("CLIP ", clip_name, " len ", a.length, " ratio ", ratio)
		src.free()
	var err := ResourceSaver.save(lib, OUT)
	print("SAVED ", err, " clips ", lib.get_animation_list().size())
	quit()

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
