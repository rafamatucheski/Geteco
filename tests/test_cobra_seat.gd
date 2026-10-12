extends SceneTree
const MODEL := preload("res://gameplay/CobraModel.gd")
const CATALOG := preload("res://assets/civilians/RoleBodyCatalog.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var car := preload("res://scripts/Vehicle.gd").new()
	car.archetype = "cobra_v8"
	car.position = Vector3(7, 2, -9)
	car.rotation.y = .7
	stage.add_child(car)
	car.set_physics_process(false)
	var cabin: Dictionary = INTERIOR.spec(car)
	for imported in [true, false]:
		CATALOG.enabled = imported
		for tier in 3:
			for driver in [true, false]:
				var model := MODEL.new()
				model.tier = tier
				model.seated = true
				model.seat_armed = true
				model.position = Vector3(float(cabin.sx) if driver else -float(cabin.sx), cabin.floor, cabin.sz)
				car.add_child(model)
				model.fit_seat(car, cabin, driver)
				var label := "imported=%s tier=%d driver=%s" % [imported, tier, driver]
				check((model.body._meshy != null) == imported, label + " correct body path")
				check(model._seat_hands.is_valid(), label + " seat fitting completed")
				check(model.body.scale.is_finite() and model.body.scale.y > 0, label + " valid body scale")
				var top: float = model._seated_head_top(car)
				check(top <= float(cabin.roof) - .02, label + " crown below roof (%.3f < %.3f)" % [top, cabin.roof])
				var hands: Array = model._seat_hands.call()
				check(hands.size() == 2 and hands[0] is Vector3 and hands[1] is Vector3, label + " wheel/lap hand targets")
				model.free()
	stage.free()
	print("COBRA_SEAT failures=", failures)
	quit(0 if failures.is_empty() else 1)
