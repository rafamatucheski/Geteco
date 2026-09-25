extends SceneTree

const FALL := preload("res://gameplay/CharacterFallPresentation3D.gd")
const EFFECTS := preload("res://gameplay/CombatEffects.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: " + message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func run() -> void:
	var actor := Node3D.new()
	var visual := Node3D.new()
	actor.add_child(visual)
	root.add_child(actor)
	for name in ["left_upper_leg", "right_upper_leg", "left_upper_arm", "right_upper_arm"]:
		var limb := Node3D.new()
		limb.name = name
		visual.add_child(limb)
	FALL.apply_fall(actor, visual, Vector3(0, 0, 1))
	await create_timer(.18).timeout
	check(visual.rotation.x > .01, "Fall pitches the visual after impact")
	check(visual.get_node("left_upper_arm").rotation.length() > .01, "Fall braces articulated limbs")
	await create_timer(1.1).timeout
	check(visual.rotation.x > 1.3, "Fall settles near the ground")
	actor.queue_free()
	var effects: Node3D = EFFECTS.new()
	root.add_child(effects)
	effects.blood(Vector3(0, 1, 0), Vector3.RIGHT, 30.0)
	effects.muzzle_smoke(Vector3(0, 1, 0), Vector3.FORWARD)
	for material in ["concrete", "wood", "metal", "flesh", "glass", "world"]:
		effects.impact(Vector3(0, 1, 0), Vector3.UP, material, 20.0)
	effects.stain(Vector3.ZERO, .75)
	effects._physics_process(.1)
	effects._physics_process(1.2)
	effects._physics_process(2.4)
	check(true, "Combat effects accept blood, smoke, impacts and stain")
	effects.clear()
	effects.shutdown()
	effects.queue_free()
	await process_frame
	print("V1_COMBAT_PARITY ", "PASS" if failures.is_empty() else "FAIL", " checks=4 failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
