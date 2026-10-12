extends SceneTree
const RACE := preload("res://activities/desert_drag/DesertDrag.gd")
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var full: Dictionary = RACE.rival_parts("takeshi")
	var middle := {"engine":"race_cam","turbo":"turbo_mid","tires":"drag_tires","nitro":"nitro_street","suspension":"drag_suspension"}
	var rival := run_car("supra_a80",full,float(RACE.TAKESHI.reaction))
	var stock := run_car("desert_mirage",{},0.0)
	var prepared := run_car("desert_mirage",middle,0.0)
	var expert := run_car("desert_mirage",full,0.0)
	var poor := run_car("desert_mirage",full,0.0,.72,.9)
	var no_nitro := run_car("desert_mirage",full,0.0,.91,.52,false)
	print("TAKESHI_BALANCE seconds=",JSON.stringify({"rival":rival,"stock":stock,"middle":prepared,"full_expert":expert,"full_poor":poor,"full_no_nitro":no_nitro}))
	check(TUNING.clean_parts(full)==full,"Takeshi uses real available tuning parts")
	check(rival<stock-1.0 and rival<prepared-.5,"stock and half-prepared sports cars cannot win with clean shifts")
	check(expert<rival and rival-expert<.85,"fully prepared sports car can win with a narrow skill margin")
	check(poor>rival,"wheelspin and early shifts lose even with a fully prepared sports car")
	check(no_nitro>rival,"full car still needs well-used nitro to beat Takeshi")
	check(RACE.RIVALS.size()==6,"honor challenge remains separate from the ordinary championship")
	print("TAKESHI_BALANCE failures=",failures)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool,label: String) -> void:
	print("TAKESHI_BALANCE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run_car(model: String, parts: Dictionary, reaction: float, shift_ratio := .91, launch_pedal := .52, nitro := true) -> float:
	var drive := DRIVE.new()
	drive.configure(model,parts)
	drive.launch_blend_seconds = .35
	drive.stage(1.0,launch_pedal)
	drive.launch()
	var seconds := 0.0
	var shift_wait := -1.0
	const STEP := 1.0/60.0
	while seconds<65 and drive.distance_m<800:
		if drive.rpm>=drive.redline*shift_ratio:
			if shift_wait<0: shift_wait=.04
			shift_wait-=STEP
			if shift_wait<=0:
				drive.shift_up()
				shift_wait=-1
		drive.step(STEP,1.0 if seconds>=reaction else 0.0,nitro and drive.gear>=3 and seconds>6.0)
		seconds+=STEP
	return seconds
