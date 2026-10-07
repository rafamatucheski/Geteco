extends SceneTree
const Retarget := preload("res://tools/retarget_ual_to_dante.gd")
func _init() -> void:
	var dst: Node = (load("res://assets/dante.glb") as PackedScene).instantiate()
	root.add_child(dst)
	var ds: Skeleton3D = dst.find_child("Skeleton3D", true, false)
	var lib: AnimationLibrary = load("res://assets/animation_library/dante_ual.res")
	var hips := ds.find_bone("Hips")
	for clip in ["Punch_Jab", "Punch_Cross", "Punch_Enter", "Sword_Attack"]:
		var a: Animation = lib.get_animation(clip)
		var prev := {}
		var best := {"Left": [0.0, 0.0], "Right": [0.0, 0.0]}
		var t := 0.0
		while t <= a.length + 0.0001:
			for i in ds.get_bone_count(): ds.set_bone_pose(i, ds.get_bone_rest(i))
			for tr in a.get_track_count():
				var bone := ds.find_bone(str(a.track_get_path(tr)).get_slice(":", 1))
				if bone < 0: continue
				if a.track_get_type(tr) == Animation.TYPE_ROTATION_3D: ds.set_bone_pose_rotation(bone, a.rotation_track_interpolate(tr, t))
				elif a.track_get_type(tr) == Animation.TYPE_POSITION_3D: ds.set_bone_pose_position(bone, a.position_track_interpolate(tr, t))
			var hip_pos: Vector3 = Retarget.chain(ds, hips).origin
			for side in ["Left", "Right"]:
				var p: Vector3 = Retarget.chain(ds, ds.find_bone(side + "Hand")).origin
				# velocidade da mão relativa ao quadril (o corpo andando não conta) e avanço à frente (+Z do esqueleto)
				var rel := p - hip_pos
				if prev.has(side):
					var speed: float = (rel - prev[side]).length() * 30.0
					if speed > best[side][0]: best[side] = [speed, t]
				prev[side] = rel
			t += 1.0 / 30.0
		print("PUNCH ", clip, " len=", snapped(a.length, 0.01), " Left pico ", snapped(best.Left[0], 0.1), " m/s em t=", snapped(best.Left[1], 0.01), " | Right pico ", snapped(best.Right[0], 0.1), " m/s em t=", snapped(best.Right[1], 0.01))
	quit()
