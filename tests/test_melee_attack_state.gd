extends SceneTree
## Regression: switching away from a heavy combo must not carry its hit-stop,
## heavy flag or combo pitch step into knife, katana or firearms.
const POSE = preload("res://gameplay/WeaponRigPose.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("MELEE_ATTACK_STATE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	for next_id in ["knife", "katana", "pistol"]:
		var pose := POSE.new()
		pose.attack("bat")
		pose.attack("bat")
		pose.attack("bat")
		check(pose.heavy_attack(), "bat finisher is heavy before switching to " + next_id)
		pose.impact("bat")
		check(pose.hit_stop > 0.0, "bat contact holds presentation before " + next_id)
		pose.attack(next_id)
		check(not pose.heavy_attack(), next_id + " does not inherit heavy finisher")
		check(is_zero_approx(pose.hit_stop), next_id + " starts without stale hit-stop")
		check(pose.combo_step == 0, next_id + " does not inherit heavy combo pitch")
		if next_id != "pistol":
			pose.impact(next_id)
			check(is_equal_approx(pose.hit_stop, float(POSE.HIT_STOP[next_id])), next_id + " uses its own impact duration")
	var ordinary := POSE.new()
	var forged := POSE.new()
	ordinary.attack("knife")
	forged.attack("knife")
	ordinary.update("knife", 0.02, true, false, 0.0, true, true, 0.0, {"action_rate": 1.0})
	forged.update("knife", 0.02, true, false, 0.0, true, true, 0.0, {"action_rate": 2.0})
	check(is_equal_approx(forged.action_age, ordinary.action_age * 2.0), "forged speed advances the attack clock")
	check(is_equal_approx(forged._move_weight, ordinary._move_weight) and is_equal_approx(forged._sprint_weight, ordinary._sprint_weight), "forged speed preserves movement blending")
	ordinary.impact("knife")
	forged.impact("knife")
	ordinary.update("knife", 0.01, true, false, 0.0, true, true, 0.0, {"action_rate": 1.0})
	forged.update("knife", 0.01, true, false, 0.0, true, true, 0.0, {"action_rate": 2.0})
	check(is_equal_approx(forged.hit_stop, ordinary.hit_stop), "forged speed preserves real-time impact pause")
	print("MELEE_ATTACK_STATE failures=", failures)
	quit(0 if failures.is_empty() else 1)
