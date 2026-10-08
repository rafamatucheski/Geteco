extends SceneTree
# Diagnóstico temporário: orientação do Dante (lado esquerdo e direção de queda de dying_backwards).
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var dst: Node = (load("res://assets/dante.glb") as PackedScene).instantiate()
	root.add_child(dst)
	var ds: Skeleton3D = dst.find_child("Skeleton3D", true, false)
	var dap := dst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	dap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var lu := ds.find_bone("LeftUpLeg"); var ru := ds.find_bone("RightUpLeg")
	print("REST LeftUpLeg ", ds.get_bone_global_rest(lu).origin, " RightUpLeg ", ds.get_bone_global_rest(ru).origin)
	var hips := ds.find_bone("Hips")
	dap.play("dying_backwards")
	for t in [0.0, dap.current_animation_length]:
		dap.seek(t, true); dap.advance(0.0); await process_frame
		print("DYING t=", snappedf(t,0.01), " hips ", ds.get_bone_global_pose(hips).origin.snapped(Vector3.ONE*0.01))
	quit()
