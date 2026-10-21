extends SceneTree
## Real production wheel rigs: small per-step turns must remain visible while
## wheel roll, rear axle and player steering retain their independent axes.
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	for id in ["union_sedan", "metro_hatch", "besouro_1300"]:
		var car := VEHICLE.new()
		car.archetype = id
		stage.add_child(car)
		car.set_physics_process(false)
		car.traffic = true
		check(car.wheels.size() == 4, id+": four animated wheels")
		for turn in [-0.005, 0.005, 0.0]:
			car.speed = 4.0
			car._motion_start_yaw = PI-0.002
			car.rotation.y = wrapf(car._motion_start_yaw+turn,-PI,PI)
			car._tick_motion_presentation(1.0/60.0, -car.global_basis.z/15.0, Vector3.ZERO, -car.global_basis.z)
			check(absf(car.steering) > .15 if turn != 0 else is_zero_approx(car.steering), id+": sustained bend / straight "+str(turn))
			if turn != 0.0:
				check(signf(car.steering) == signf(turn), id+": correct turn side across yaw wrap")
			for wheel in car.wheels:
				var expected: float = car.steering if wheel.get_meta("front") else 0.0
				check(is_equal_approx(wheel.rotation.y,expected), id+": front steers, rear stays straight")
				check(absf(wheel.rotation.x) > .01, id+": wheel continues rolling")
		car.speed = 0.0
		car._tick_motion_presentation(0.0,Vector3.ZERO,Vector3.ZERO,Vector3.FORWARD)
		check(is_zero_approx(car.steering), id+": stopped car has finite straight wheels")
		car.traffic = false
		car.steering = -.3
		car._tick_motion_presentation(1.0/60.0,Vector3.ZERO,Vector3.ZERO,Vector3.FORWARD)
		check(is_equal_approx(car.steering,-.3), id+": player steering preserved")
		car.free()
	stage.free()
	print("TRAFFIC_WHEEL_STEERING checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
