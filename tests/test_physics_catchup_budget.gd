extends SceneTree

func _initialize() -> void:
	var failures: Array[String] = []
	_check(Engine.physics_ticks_per_second == 60, "Physics remains at 60 Hz", failures)
	_check(Engine.max_physics_steps_per_frame == 2, "Runtime catch-up is bounded to two steps per rendered frame", failures)
	_check(bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)), "Physics interpolation remains enabled", failures)
	print("PHYSICS_CATCHUP_BUDGET failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String, failures: Array[String]) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)
