extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func _run() -> void:
	var yard := Node2D.new()
	yard.rotation = 0.23
	root.add_child(yard)
	for id in ["police_cruiser", "police_suv", "american_flatbed", "cargo_flatbed_truck"]:
		var car := ModernTrafficFactory.spawn_parked_vehicle(yard, id, Vector2(320, 240), PI * 0.5, id, 0, Color.WHITE, false)
		car.ensure_presentation()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("out_dir="):
					var output := arg.trim_prefix("out_dir=")
					DirAccess.make_dir_recursive_absolute(output)
					root.get_texture().get_image().save_png(output.path_join(id + ".png"))
		_check(not car.is_processing() and not car.is_physics_processing(), id + " stays idle")
		_check(absf(angle_difference(car.visual.global_rotation, 0.0)) < 0.001, id + " sprite stays aligned to the screen before boarding")
		var initial_heading: float = car.body_model.rotation.y
		car._update_3d_orientation(0.0)
		_check(absf(angle_difference(initial_heading, car.body_model.rotation.y)) < 0.001, id + " first driving update does not turn the body")
		car.free()
	yard.free()
	print("PARKED_INITIAL_HEADING failures=", failures)
	quit(0 if failures.is_empty() else 1)
