extends SceneTree
const VEHICLE := preload("res://scripts/Vehicle.gd")
const STREET := preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error(label)

func run() -> void:
	for id in STREET.ids() + ["desert_faisca"]:
		var car = VEHICLE.new()
		car.archetype = id
		root.add_child(car)
		car.set_physics_process(false)
		if car.handling.get("drive") == null:
			preload("res://gameplay/desert_cars/DesertCarAdapter.gd").attach(car)
		var speeds := []
		for hz in [30, 60, 120]:
			car.handling.reset()
			car.speed = 20.0
			car.horizontal_velocity = Vector3(0, 0, -20)
			var previous := 20.0
			for tick in hz * 3:
				car.handling.step(car, 1.0/hz, 0.0, 0.0, false, 0.0)
				check(car.speed >= 0 and car.speed <= previous, id+": coast must slow monotonically without reversing")
				previous = car.speed
			speeds.append(car.speed)
			check(car.speed > 8.0 and car.speed < 16.0, id+": release must lose noticeable speed progressively over three seconds: "+str(car.speed))
			for tick in hz * 20: car.handling.step(car, 1.0/hz, 0.0, 0.0, false, 0.0)
			check(car.speed == 0.0, id+": must eventually stop without reverse creep")
		check(absf(speeds[0]-speeds[2]) < .12, id+": coasting must be frame-rate independent")
		car.handling.reset()
		car.speed = 20.0
		car.horizontal_velocity = Vector3(0, 0, -20)
		for tick in 60: car.handling.step(car, 1.0/60.0, 0.0, 0.0, true, 0.0)
		check(car.speed < speeds[1], id+": active braking must beat three seconds of coast in one second")
		car.handling.reset()
		car.speed = 5.0
		car.horizontal_velocity = Vector3(0, 0, -5)
		for tick in 60: car.handling.step(car, 1.0/60.0, 1.0, 0.0, false, 0.0)
		check(car.speed > 5.0, id+": pressing the accelerator must resume acceleration")
		print("COAST ", id, " speed_after_3s=", speeds)
		car.free()
	print("COAST failures=", failures)
	quit(0 if failures == 0 else 1)
