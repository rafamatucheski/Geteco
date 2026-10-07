extends SceneTree
const Retarget := preload("res://tools/retarget_ual_to_dante.gd")
## Compara a direção de cada segmento do corpo (coxa, canela, braço, antebraço, tronco)
## entre a animação original e a do Dante. Direção, não posição: os rigs têm proporções
## diferentes, então distância de membro mede o tamanho do boneco, não o retarget.
const SEGS := [["LeftUpLeg","LeftLeg","DEF-thigh.L","DEF-shin.L"],["LeftLeg","LeftFoot","DEF-shin.L","DEF-foot.L"],
	["RightUpLeg","RightLeg","DEF-thigh.R","DEF-shin.R"],["RightLeg","RightFoot","DEF-shin.R","DEF-foot.R"],
	["LeftArm","LeftForeArm","DEF-upper_arm.L","DEF-forearm.L"],["LeftForeArm","LeftHand","DEF-forearm.L","DEF-hand.L"],
	["RightArm","RightForeArm","DEF-upper_arm.R","DEF-forearm.R"],["RightForeArm","RightHand","DEF-forearm.R","DEF-hand.R"],
	["Hips","Head","DEF-hips","DEF-head"]]
func _init() -> void:
	var src: Node = (load("res://assets/animation_library/AnimationLibrary_Godot_Standard.glb") as PackedScene).instantiate()
	var dst: Node = (load("res://assets/dante.glb") as PackedScene).instantiate()
	root.add_child(src); root.add_child(dst)
	var ss: Skeleton3D = src.find_child("Skeleton3D", true, false)
	var ds: Skeleton3D = dst.find_child("Skeleton3D", true, false)
	var sap := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var dap := dst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	dap.add_animation_library("ual", load("res://assets/animation_library/dante_ual.res"))
	for clip in ["Walk", "Jog_Fwd", "Sitting_Idle", "Death01", "Swim_Fwd", "Punch_Jab", "Pistol_Aim_Neutral", "Sprint", "Roll"]:
		var worst := 0.0; var where := ""
		var len := sap.get_animation(clip).length
		for k in 8:
			var t := len * k / 8.0
			sap.play(clip); sap.seek(t, true); sap.pause(); sap.advance(0)
			dap.play("ual/" + clip); dap.seek(t, true); dap.pause(); dap.advance(0)
			for s in SEGS:
				var a: Vector3 = (Retarget.chain(ss, ss.find_bone(s[3])).origin - Retarget.chain(ss, ss.find_bone(s[2])).origin).normalized()
				var b: Vector3 = (Retarget.chain(ds, ds.find_bone(s[1])).origin - Retarget.chain(ds, ds.find_bone(s[0])).origin).normalized()
				var ang := rad_to_deg(a.angle_to(b))
				if ang > worst: worst = ang; where = s[0]
		print("CLIP %s pior ângulo de segmento %.1f° (%s)" % [clip, worst, where])
	quit()
