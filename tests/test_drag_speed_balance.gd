extends SceneTree
## Compare the authored engine simulation with actual race world motion.
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	for id in ["desert_faisca", "desert_mirage", "porto_rosso"]:
		for racing in [false, true]:
			var balanced := DRIVE.new()
			var mechanical := DRIVE.new()
			for drive in [balanced, mechanical]:
				drive.race_mode = racing
				drive.configure(id)
				drive.stage(1.0, .54)
				drive.launch()
			# The reference remains inside the engine's mechanical coordinate system.
			mechanical._integrating = true
			var factor := .75 if racing else 1.0
			for tick in 1200:
				if balanced.rpm >= balanced.ideal_shift_rpm:
					balanced.shift_up()
					mechanical.shift_up()
				var brake := .6 if tick >= 960 else 0.0
				balanced.step(1.0/120.0, 1.0, tick > 600, brake)
				mechanical._integrate(1.0/120.0, 1.0, tick > 600, brake)
				check(absf(balanced.speed_mps - mechanical.speed_mps * factor) < .00001, id + " physical velocity is 25 percent slower only in race mode")
				check(absf(balanced.distance_m - mechanical.distance_m * factor) < .00001, id + " telemetry and finish distance match physical speed")
				check(absf(balanced.rpm - mechanical.rpm) < .001 and balanced.gear == mechanical.gear, id + " RPM and gearbox remain coupled across shifts and braking")
			for road_speed in [3.0, 12.0, 28.0]:
				balanced.follow_external_motion(road_speed * factor, 1.0, .1)
				mechanical.follow_external_motion(road_speed, 1.0, .1)
				check(absf(balanced.rpm - mechanical.rpm) < .001 and balanced.gear == mechanical.gear, id + " external driver reports the same coupled gearbox state at reduced world speed")
	print("DRAG_SPEED_BALANCE checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and label not in failures:
		failures.append(label)
		push_error(label)
