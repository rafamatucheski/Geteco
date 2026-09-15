extends "res://tests/measure_city_scenarios.gd"
## Optional baseline reload affects only this process, never workspace files.
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("baseline_source="): continue
		var folder := arg.trim_prefix("baseline_source=")
		for path in ["PedestrianDanger.gd", "Paramedic.gd", "world/shared/emergency/MedicalRescueSequence.gd", "world/shared/combat/BulletReaction.gd", "Bullet.gd"]:
			var script := load("res://" + path) as GDScript
			script.source_code = FileAccess.get_file_as_string(folder.path_join(path))
			var error := script.reload()
			if error != OK:
				push_error("Baseline reload failed: " + path)
				quit(2)
				return
	await super._run()
