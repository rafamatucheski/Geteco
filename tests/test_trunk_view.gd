extends SceneTree
## Isolated validator for res://runtime/TrunkView.gd, the V2 presentation of
## the Monaliza trunk (real 3D lid + weapon models, no PersonalCar/session
## plumbing needed to exercise it).
class MockCar extends Node3D:
	var visual: Node3D
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var car := MockCar.new()
	root.add_child(car)
	var visual := Node3D.new()
	car.add_child(visual)
	car.visual = visual
	var pivot := Node3D.new()
	pivot.name = "MonalizaTrunkHinge"
	visual.add_child(pivot)
	var camera := preload("res://scripts/CameraRig.gd").new()
	root.add_child(camera)
	camera.target = car
	camera.locked = false
	camera.offset = Vector3(1, 2, 3)
	camera.target_size = 20.0

	var view = preload("res://runtime/TrunkView.gd").new()
	root.add_child(view)
	view.open(car, camera)
	check(view.pivot == pivot, "Trunk view did not find the MonalizaTrunkHinge pivot")
	check(camera.locked and camera.target == car, "Camera did not lock onto the car for the trunk shot")
	for frame in 30: await process_frame
	check(pivot.rotation.x < -1.5, "Trunk lid never opened (rotation.x=%s)" % pivot.rotation.x)
	check(view.weapons.position.y > 0.15, "Loadout tray never rose (y=%s)" % view.weapons.position.y)

	view.update_loadout({"curta": "pistol", "longa": "", "corpo": "", "granada": ""})
	await process_frame
	check(view.slot_models.get("curta") != null and is_instance_valid(view.slot_models.curta), "Pistol slot has no model after update_loadout")
	check(view.slot_models.curta.get_child_count() > 0, "Pistol slot model has no built geometry")
	check(str(view.displayed.get("longa","x")) == "", "Empty slot should stay empty")

	view.update_loadout({"curta": "", "longa": "", "corpo": "", "granada": ""})
	await process_frame
	check(view.slot_models.curta.get_child_count() == 0, "Cleared slot still shows a weapon model")

	view.close()
	await process_frame
	check(pivot.rotation.x == 0.0, "Trunk lid did not close")
	check(not camera.locked and camera.target == car, "Camera framing was not restored after close")
	check(not is_instance_valid(view) or view.is_queued_for_deletion(), "TrunkView did not free itself on close")

	for failure in failures: push_error(failure)
	print("TRUNK_VIEW ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
