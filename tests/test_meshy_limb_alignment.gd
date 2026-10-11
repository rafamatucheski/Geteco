extends SceneTree
## Juntas públicas comandam a marcha/queda. O esqueleto visível precisa manter joelhos e tornozelos nessas juntas.
const BODY := preload("res://assets/CivilianModel.gd")
var sources: Array = ["res://assets/civilians/meshy/police/suit_m.glb", "res://assets/civilians/meshy/police/patrol_m.glb"]
var failures: Array[String] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--body="): sources = [arg.substr(7)]
	_run.call_deferred()

func _run() -> void:
	for source in sources:
		var model := BODY.new()
		model.body_source = String(source)
		model.appearance_locked = true
		model.appearance_variant = 0
		model.lod_enabled = false
		root.add_child(model)
		model.set_process(false)
		for pose in [["neutral", 0.0, 0.0], ["stride", .65, .9], ["seated", -1.0, 1.3], ["fall", .9, -.7]]:
			model.pelvis.rotation = Vector3(.2, .1, .1) if pose[0] == "fall" else Vector3.ZERO
			model.pelvis.position.y = model.pelvis_y - (.4 if pose[0] == "seated" else 0.0)
			for side in 2:
				model.thighs[side].rotation = Vector3(float(pose[1]) * (1.0 if side == 0 else -1.0), 0, 0)
				model.shins[side].rotation = Vector3(float(pose[2]), 0, 0)
			await process_frame
			await create_timer(0.0).timeout
			for side in 2:
				var prefix := "Right" if side == 0 else "Left"
				for part in [["Leg", model.shins[side]], ["Foot", model.feet[side]]]:
					var bone: int = model.skeleton.find_bone("mixamorig_" + prefix + String(part[0]))
					var actual: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(bone).origin
					var error_mm: float = actual.distance_to(part[1].global_position) * 1000.0
					var ok := is_finite(error_mm) and error_mm < 20.0
					var label := "%s/%s/%s%s %.3f mm" % [String(source).get_file(), pose[0], prefix, part[0], error_mm]
					print("MESHY_MEMBRO ", "PASS " if ok else "FAIL ", label)
					if not ok: failures.append(label)
		model.queue_free()
		await process_frame
	print("MESHY_MEMBRO failures=", failures)
	quit(0 if failures.is_empty() else 1)
