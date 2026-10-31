extends SceneTree
## Contratos dirigidos para o pedal só de corrida e a transmissão contínua.
## A preparação binária usa entradas reais 0/1, nunca a antiga sobrescrita analógica de .54.
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const RACE := preload("res://activities/desert_drag/DesertDrag.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	for hz in [30,60,120]:
		_check_binary_staging(hz)
	_check_launch_continuity()
	_check_shift_continuity()
	_check_competitive_times()
	print("DRAG_CONTROL_FEEL checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _drive(id := "desert_faisca", parts: Dictionary = {}, improved := true):
	var drive := DRIVE.new()
	drive.configure(id,parts)
	drive.race_mode = improved
	drive.launch_blend_seconds = .35
	return drive

func _check_binary_staging(hz: int) -> void:
	var dt := 1.0/float(hz)
	var held = _drive()
	var good_seconds := 0.0
	for _i in hz*3:
		held.stage(dt,1.0,true)
		if held.rpm/held.redline >= DRIVE.LAUNCH_GOOD_MIN and held.rpm/held.redline <= DRIVE.LAUNCH_GOOD_MAX:
			good_seconds += dt
	check(good_seconds >= .65,"keyboard has a readable good launch window at %d Hz"%hz)
	check(held.rpm > held.redline*.9,"holding W can still over-rev; assistance does not auto-aim at perfect RPM")
	var pulsed = _drive()
	# Dois toques deliberados com pausas generosas: um rastro de ação em escala humana.
	# Isto não é um controlador com realimentação que sabe o RPM ideal exato.
	for i in hz*3:
		var time := float(i)*dt
		var pedal := 1.0 if time<1.35 or (time>=1.85 and time<2.55) else 0.0
		pulsed.stage(dt,pedal,true)
	var ratio: float = pulsed.rpm/pulsed.redline
	check(ratio>=DRIVE.LAUNCH_GOOD_MIN and ratio<=DRIVE.LAUNCH_GOOD_MAX,"two binary presses achieve a good launch at %d Hz"%hz)
	var analog = _drive()
	for _i in hz*3: analog.stage(dt,.50,false)
	check(absf(analog.rpm-lerpf(900.0,analog.redline,.50))<1.0,"analogue pedal retains its stable intermediate target at %d Hz"%hz)
	print("DRAG_BINARY hz=",hz," good_window_seconds=",good_seconds," pulse_ratio=",ratio)

func _check_launch_continuity() -> void:
	for boundary in [DRIVE.LAUNCH_GOOD_MIN,DRIVE.LAUNCH_PERFECT_MIN,DRIVE.LAUNCH_PERFECT_MAX,DRIVE.LAUNCH_GOOD_MAX]:
		var before = _drive()
		var after = _drive()
		before.rpm = before.redline*(boundary-.0001)
		after.rpm = after.redline*(boundary+.0001)
		before.launch()
		after.launch()
		for _i in 120:
			before.step(1.0/120.0,1.0,false)
			after.step(1.0/120.0,1.0,false)
		check(absf(before.speed_mps-after.speed_mps)<.02,"launch traction has no cliff at ratio %.2f"%boundary)

func _check_shift_continuity() -> void:
	var drive = _drive()
	drive.rpm = drive.redline*.54
	drive.launch()
	for _i in 1200:
		drive.step(1.0/120.0,1.0,false)
		if drive.rpm >= drive.ideal_shift_rpm: break
	var before_rpm: float = drive.rpm
	var before_speed: float = drive.speed_mps
	var accepted: String = drive.shift_up()
	check(not accepted.is_empty(),"a valid shift is accepted")
	check(is_equal_approx(drive.rpm,before_rpm),"requesting a shift never teleports engine RPM")
	check(is_equal_approx(drive.speed_mps,before_speed),"requesting a shift never awards velocity")
	var serial: int = drive.shift_serial
	check(drive.shift_up().is_empty() and drive.shift_serial==serial,"extra press cannot enqueue another gear or destroy the accepted shift")
	var partial_torque := false
	var max_rpm_step := 0.0
	for _i in 90:
		var previous_rpm: float = drive.rpm
		drive.step(1.0/120.0,1.0,false)
		max_rpm_step = maxf(max_rpm_step,absf(drive.rpm-previous_rpm))
		partial_torque = partial_torque or (drive.shift_torque_factor>.01 and drive.shift_torque_factor<.99)
		check(drive.shift_torque_factor>=0.0 and drive.shift_torque_factor<=1.0,"clutch transmits a bounded share of engine force")
	check(partial_torque,"disengagement and re-engagement pass through partial force")
	check(max_rpm_step<drive.redline*.10,"no shift tick contains the full gear-ratio RPM fall")
	check(drive.gear==2 and drive.shift_remaining<=0.0,"one press completes exactly one upshift")
	drive.gear = drive.spec.gears.size()
	serial = drive.shift_serial
	check(drive.shift_up()=="max" and drive.shift_serial==serial,"last gear reports max without emitting a shift")

func _check_competitive_times() -> void:
	var prepared := {"engine":"race_cam","turbo":"turbo_large","nitro":"nitro_race","tires":"drag_tires","weight":"lightweight"}
	for id in ["desert_faisca","desert_mirage","porto_rosso"]:
		var stock := _run(id,{},true)
		var legacy := _run(id,{},false)
		var upgraded := _run(id,prepared,true)
		var early := _run(id,{},true,.70)
		check(absf(stock-legacy)<=legacy*.05,"continuous clutch preserves pace against the equally speed-balanced reference within 5 percent: "+id)
		check(upgraded<stock-.25,"real purchasable preparation still improves 800 m: "+id)
		check(early>stock+.25,"early shifting still costs measurable time: "+id)
		print("DRAG_FEEL_TIMING car=",id," legacy=",legacy," stock=",stock," upgraded=",upgraded," early=",early)
	var previous := INF
	for identity in RACE.RIVALS:
		var config: Dictionary = RACE.RIVALS[identity]
		var elapsed := _run(str(config.car),RACE.rival_parts(identity),true,.91,float(config.reaction))
		check(elapsed<previous,"authored rival ladder remains progressively faster: "+str(identity))
		previous = elapsed
		print("DRAG_FEEL_RIVAL id=",identity," seconds=",elapsed)

func _run(id: String, parts: Dictionary, improved: bool, shift_ratio := .91, reaction := 0.0) -> float:
	var drive = _drive(id,parts,improved)
	drive.rpm = drive.redline*.54
	drive.launch()
	const DT := 1.0/120.0
	var elapsed := 0.0
	# O legado é uma referência mecânica sem a escala de mundo da corrida. Compara a
	# mesma distância do motor: 1066.67 metros mecânicos agora cobrem 800 metros do mundo.
	var engine_distance := 800.0 if improved else 800.0 / .75
	while elapsed<65.0 and drive.distance_m<engine_distance:
		if drive.rpm>=drive.redline*shift_ratio: drive.shift_up()
		drive.step(DT,1.0 if elapsed>=reaction else 0.0,drive.gear>=3 and elapsed>6.0)
		elapsed += DT
	return elapsed
