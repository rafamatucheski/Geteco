extends SceneTree

const CADENCE := preload("res://audio/FootstepCadence.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	var slow_stride := CADENCE.stride(1.6)
	check(is_equal_approx(slow_stride, CADENCE.MIN_STRIDE), "walking cadence is capped at about 2 steps per second")
	var sprint_stride := CADENCE.stride(6.5)
	check(is_equal_approx(sprint_stride, CADENCE.MAX_STRIDE), "sprinting cadence stays below 2.6 steps per second")
	check(sprint_stride > slow_stride, "stride length increases with movement speed")
	print("WORLD_AUDIO_FOOTSTEPS checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("CASE PASS " if ok else "CASE FAIL ") + label)
	if not ok: failures.append(label)
