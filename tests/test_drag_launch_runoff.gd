extends SceneTree

const DRIVE = preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const RACE = preload("res://activities/desert_drag/DesertDrag.gd")
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for pedal in [0.0,.52,1.0]:
		var drive = DRIVE.new()
		drive.configure("desert_mirage")
		drive.launch_blend_seconds = .35
		drive.stage(2.0,pedal)
		var rpm: float = drive.rpm
		drive.launch()
		drive.step(1.0/60.0,1.0,false)
		check(absf(drive.rpm-rpm)<drive.redline*.025,"staged RPM continues smoothly at green")
		check(drive.speed_mps>0 and drive.speed_mps<.025,"launch engages progressively without delay or velocity impulse")
		for i in 60: drive.step(1.0/60.0,1.0,false)
		check(drive.speed_mps>2.0,"clutch fully engages after launch")
	var race = RACE.new()
	root.add_child(race)
	for hz in [30,60,120]:
		for initial in [30.0,60.0,80.0,100.0]:
			var drive = DRIVE.new()
			drive.configure("desert_mirage")
			drive.launch()
			drive.speed_mps = initial
			var car := Node3D.new()
			root.add_child(car)
			car.global_position = race.start_point+race.direction*race.distance
			var entry := {"drive":drive,"car":car}
			var duration := 0.0
			while drive.speed_mps>.01 and duration<15.0:
				var before: float = drive.speed_mps
				race._step_runoff(entry,1.0/hz)
				check(drive.speed_mps<=before,"runoff never accelerates or reverses")
				if duration==0.0: check(before-drive.speed_mps<.25,"finish has no speed cut")
				car.global_position += race.direction*drive.speed_mps/hz
				duration += 1.0/hz
			var travelled: float = race._offset(car.global_position)-race.distance
			check(drive.speed_mps<=.01 and travelled<175.0,"stops inside runoff at %s m/s %s Hz (%s m)"%[initial,hz,travelled])
			print("DRAG_RUNOFF speed=",initial," hz=",hz," distance=",travelled," seconds=",duration)
			car.free()
	race.free()
	print("DRAG_FEEL ","PASS" if failures.is_empty() else "FAIL", " failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
