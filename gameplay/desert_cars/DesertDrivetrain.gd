extends RefCounted
## One gearbox state drives motion, tachometer and audio. No speed bonuses on shift.
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const SPEED_FACTOR := preload("res://data/catalogs/VehicleSpeedBalance.gd").FACTOR
const LAUNCH_GOOD_MIN := .38
const LAUNCH_GOOD_MAX := .70
const LAUNCH_PERFECT_MIN := .48
const LAUNCH_PERFECT_MAX := .60
var spec: Dictionary = {}
var car_id := "desert_faisca"
var rpm := 900.0
var redline := 6900.0
var ideal_shift_rpm := 6350.0
var speed_mps := 0.0
var distance_m := 0.0
var gear := 1
var nitro := 0.0
var nitro_active := false
var wheelspin := 0.0
var throttle := 0.0
var turbo_pressure := 0.0
var shift_remaining := 0.0
var last_shift := ""
var launch_quality := ""
var shift_serial := 0
var limiter := false
var launched := false
var surface_grip := 1.0
var launch_blend_seconds := 0.0
## Opt in only from the drag activity; ordinary street handling keeps its calibration.
var race_mode := false
var _integrating := false
var shift_torque_factor := 1.0
var launch_score := 0.0
var _launch_blend_elapsed := 0.0
var _launch_remaining := 0.0
var _launch_factor := 1.0
var _idle := 900.0
var _shift_duration := 0.0
var _shift_from_rpm := 0.0
var _shift_target_gear := 1

func configure(id: String, parts: Dictionary = {}) -> void:
	car_id = id
	spec = TUNING.tuned_spec(id,parts)
	redline = float(spec.redline)
	_idle = 750.0 if str(spec.engine_family) == "diesel" else 900.0
	ideal_shift_rpm = redline*.91
	reset()

func reset() -> void:
	if spec.is_empty(): configure(car_id); return
	rpm = _idle
	speed_mps = 0.0
	distance_m = 0.0
	gear = 1
	nitro = 1.0 if float(spec.nitro_seconds) > 0.0 else 0.0
	nitro_active = false
	wheelspin = 0.0
	throttle = 0.0
	turbo_pressure = 0.0
	shift_remaining = 0.0
	last_shift = ""
	launch_quality = ""
	shift_serial = 0
	limiter = false
	launched = false
	_launch_remaining = 0.0
	_launch_factor = 1.0
	_launch_blend_elapsed = 0.0
	shift_torque_factor = 1.0
	launch_score = 0.0
	_integrating = false
	_shift_duration = 0.0
	_shift_from_rpm = rpm
	_shift_target_gear = 1

func stage(delta: float, pedal: float, digital_input := false) -> void:
	if launched: return
	var dt := maxf(delta,0.0)
	var target_pedal := clampf(pedal,0.0,1.0)
	# A key remains a real 0/1 pedal, but no longer sweeps the entire good band
	# in 221 ms. Deliberate presses work; holding it still reaches the limiter.
	throttle = move_toward(throttle,target_pedal,dt*5.0) if race_mode and digital_input else target_pedal
	var target_rpm := lerpf(_idle,redline,throttle)
	var response := (.36 if target_rpm>rpm else .28) if race_mode and digital_input else .95
	rpm = move_toward(rpm,target_rpm,dt*redline*response)
	limiter = rpm >= redline*.985
	turbo_pressure = move_toward(turbo_pressure,throttle*clampf(rpm/redline,0.0,1.0),maxf(delta,0.0)/maxf(.1,float(spec.spool_seconds)))

func launch() -> String:
	if launched: return launch_quality
	launched = true
	var ratio := rpm/redline
	_launch_remaining = 1.5
	if race_mode:
		# Quality changes continuously, including at the boundaries of the labels.
		# A tiny miss must never suddenly remove almost half the available grip.
		var low_error := 1.0-smoothstep(0.0,LAUNCH_PERFECT_MIN,ratio)
		var high_error := smoothstep(LAUNCH_PERFECT_MAX,1.0,ratio)
		_launch_factor = 1.0-low_error*.44-high_error*.37
		launch_score = 1.0-maxf(low_error,high_error)
		if ratio>=LAUNCH_PERFECT_MIN and ratio<=LAUNCH_PERFECT_MAX: launch_quality="LARGADA IDEAL"
		elif ratio>=LAUNCH_GOOD_MIN and ratio<=LAUNCH_GOOD_MAX: launch_quality="BOA LARGADA"
		elif ratio>LAUNCH_GOOD_MAX: launch_quality="PATINOU"
		else: launch_quality="GIRO BAIXO"
		wheelspin = high_error*.9
		return launch_quality
	if ratio >= .43 and ratio <= .64:
		launch_quality = "LARGADA IDEAL"
		_launch_factor = 1.0
	elif ratio > .64:
		launch_quality = "PATINOU"
		_launch_factor = .63
		wheelspin = .9
	else:
		launch_quality = "GIRO BAIXO"
		_launch_factor = .56
	return launch_quality

func shift_up() -> String:
	if not launched or shift_remaining > 0.0: return ""
	if gear>=spec.gears.size(): return "max" if race_mode else ""
	if race_mode:
		var ratio := rpm/redline
		if ratio>=.89 and ratio<=.94:
			last_shift="TROCA IDEAL"
			_begin_race_shift(gear+1,.18)
		elif ratio>=ideal_shift_rpm*.94/redline and ratio<=.985:
			last_shift="BOA TROCA"
			_begin_race_shift(gear+1,.21)
		elif ratio<ideal_shift_rpm*.94/redline:
			last_shift="ADIANTOU"
			_begin_race_shift(gear+1,.44)
		else:
			last_shift="ATRASOU"
			_begin_race_shift(gear+1,.36)
		return last_shift
	if rpm >= ideal_shift_rpm*.94 and rpm <= redline*.985: last_shift = "TROCA IDEAL"; shift_remaining = .12
	elif rpm < ideal_shift_rpm*.94: last_shift = "ADIANTOU"; shift_remaining = .30
	else: last_shift = "ATRASOU"; shift_remaining = .24
	gear += 1
	rpm = maxf(_idle,_coupled_rpm())
	shift_serial += 1
	return last_shift

func shift_down() -> bool:
	if gear <= 1 or shift_remaining > 0.0: return false
	var prospective := _mechanical_speed()/(TAU*float(spec.wheel_radius))*60.0*float(spec.gears[gear-2])*float(spec.final_drive)
	if prospective > redline*.94: return false
	if race_mode:
		_begin_race_shift(gear-1,.27)
		return true
	gear -= 1
	rpm = maxf(_idle,_coupled_rpm())
	shift_remaining = .18
	shift_serial += 1
	return true

func _begin_race_shift(target_gear: int, duration: float) -> void:
	_shift_target_gear = target_gear
	_shift_from_rpm = rpm
	_shift_duration = duration
	shift_remaining = duration
	shift_torque_factor = 1.0
	shift_serial += 1

func _race_shift_state() -> float:
	var progress := 1.0-shift_remaining/maxf(.001,_shift_duration)
	# Unload the old gear before engaging the new ratio. The integral of this
	# envelope loses ~121 ms of drive for an ideal shift (previously 120 ms).
	shift_torque_factor = 1.0-smoothstep(0.0,.20,progress) if progress<.20 else smoothstep(.55,1.0,progress)
	if progress>=.20: gear=_shift_target_gear
	return progress

func step(delta: float, pedal: float, use_nitro: bool, brake: float = 0.0) -> void:
	if spec.is_empty(): configure(car_id)
	if not launched: stage(delta,pedal); return
	# Bounded substeps retain distance/force equivalence during a slow frame.
	var remaining := clampf(delta,0.0,.25)
	while remaining > .00001:
		var dt := minf(remaining,1.0/120.0)
		# Race motion has its own driver and bypasses the street speed limiter.
		# Keep the authored engine/gearbox in mechanical units, then convert both
		# speed and travelled distance together. HUD, collision and finish timing
		# therefore consume the same reduced world speed, with no second street scale.
		var scale := SPEED_FACTOR if race_mode else 1.0
		var prior_distance := distance_m
		speed_mps /= scale
		_integrating = true
		_integrate(dt,pedal,use_nitro,brake)
		_integrating = false
		speed_mps *= scale
		distance_m = prior_distance + (distance_m-prior_distance)*scale
		remaining -= dt

func _integrate(dt: float, pedal: float, use_nitro: bool, brake: float) -> void:
	throttle = clampf(pedal,0.0,1.0)
	var shifting := race_mode and shift_remaining>0.0
	shift_remaining = maxf(0.0,shift_remaining-dt)
	var shift_progress := _race_shift_state() if shifting else 1.0
	if not shifting: shift_torque_factor=1.0
	_launch_remaining = maxf(0.0,_launch_remaining-dt)
	# A embreagem começa a acoplar no primeiro pedal depois do verde, não no sinal:
	# o tempo de reação do rival é atraso de verdade. Correndo desde o sinal, a rampa
	# devolvia ~0,13 s dos 0,26 s de Takeshi e o Mirage completo passou a perder (18/10).
	if throttle > 0.0 or _launch_blend_elapsed > 0.0: _launch_blend_elapsed += dt
	var clutch_rpm := lerpf(_idle,redline*.45,throttle)*(1.0-smoothstep(0.0,9.0,speed_mps))
	var target_rpm := clampf(maxf(_coupled_rpm(),clutch_rpm),_idle,redline*1.025)
	# Race starts carry the staged revs into clutch engagement instead of
	# replacing them on the first physics tick. Ordinary driving keeps its adapter.
	if shifting:
		var next_rpm := speed_mps/(TAU*float(spec.wheel_radius))*60.0*float(spec.gears[_shift_target_gear-1])*float(spec.final_drive)
		rpm = lerpf(_shift_from_rpm,clampf(next_rpm,_idle,redline*1.025),smoothstep(.12,.85,shift_progress))
	elif launch_blend_seconds > 0.0 and _launch_blend_elapsed < launch_blend_seconds*2.0:
		rpm = move_toward(rpm,target_rpm,redline*dt*1.4)
	else:
		rpm = target_rpm
	limiter = _coupled_rpm() >= redline
	var rpm_ratio := clampf(rpm/redline,0.0,1.05)
	var target_boost := throttle*smoothstep(.24,.67,rpm_ratio)
	turbo_pressure = move_toward(turbo_pressure,target_boost,dt/maxf(.1,float(spec.spool_seconds)))
	nitro_active = use_nitro and nitro > .0001 and speed_mps > 3.0 and throttle > .5 and shift_remaining <= 0.0 and not limiter
	if nitro_active: nitro = maxf(0.0,nitro-dt/maxf(.1,float(spec.nitro_seconds)))
	var curve := (.53+.47*sin(clampf(rpm_ratio,0.0,1.0)*PI*.89))*lerpf(float(spec.low_response),1.0,smoothstep(.25,.65,rpm_ratio))
	var torque := float(spec.torque_nm)*curve*(1.0+float(spec.boost_gain)*turbo_pressure)
	if nitro_active: torque *= 1.0+float(spec.nitro_force)
	var force := torque*float(spec.gears[gear-1])*float(spec.final_drive)*.86/maxf(.1,float(spec.wheel_radius))*throttle
	if limiter: force=0.0
	elif race_mode: force*=shift_torque_factor
	elif shift_remaining>0.0: force=0.0
	var mass_kg := float(spec.mass)*1000.0
	var grip_force := mass_kg*9.81*float(spec.traction)*surface_grip
	if _launch_remaining > 0.0: grip_force *= lerpf(1.0,_launch_factor,_launch_remaining/1.5)
	wheelspin = move_toward(wheelspin,clampf((force-grip_force)/maxf(force,1.0),0.0,1.0),dt*3.0)
	force = minf(force,grip_force)
	if launch_blend_seconds > 0.0:
		force *= lerpf(.04,1.0,smoothstep(0.0,launch_blend_seconds,_launch_blend_elapsed))
	var resistance := .5*1.20*float(spec.drag_area)*speed_mps*speed_mps+mass_kg*9.81*.015
	var before := speed_mps
	speed_mps = maxf(0.0,speed_mps+(force-resistance)/mass_kg*dt-clampf(brake,0.0,1.0)*10.5*dt)
	distance_m += (before+speed_mps)*.5*dt

func _coupled_rpm() -> float:
	return _mechanical_speed()/(TAU*float(spec.wheel_radius))*60.0*float(spec.gears[gear-1])*float(spec.final_drive)

func _mechanical_speed() -> float:
	return speed_mps / SPEED_FACTOR if race_mode and not _integrating else speed_mps

func synchronize(actual_speed: float, pedal: float, reverse := false) -> void:
	# Collision/reverse adapter uses real wheel speed, never an estimated shift.
	speed_mps = maxf(0.0,absf(actual_speed))
	if reverse: gear = 1
	throttle = clampf(pedal,0.0,1.0)
	rpm = clampf(maxf(_idle,_coupled_rpm()),_idle,redline)
	nitro_active = false
	limiter = rpm >= redline

func follow_external_motion(actual_speed: float, pedal: float, delta: float) -> void:
	# Native route/external drivers own movement and do not call Handling.step.
	# Observe their real wheel speed using this gearbox's ratios, without adding
	# force, distance, launch bonuses or changing the nitro reserve.
	if spec.is_empty(): return
	var mechanical_speed := absf(actual_speed)/(SPEED_FACTOR if race_mode and not _integrating else 1.0)
	var wheel_rpm := mechanical_speed/(TAU*float(spec.wheel_radius))*60.0*float(spec.final_drive)
	gear = 1
	if actual_speed >= 0.0:
		while gear < spec.gears.size() and wheel_rpm*float(spec.gears[gear-1]) > ideal_shift_rpm:
			gear += 1
	# Native external driving resets Handling each physics tick. This observer
	# must not manufacture a repeated manual-shift cut/event after every reset.
	shift_remaining = 0.0
	synchronize(actual_speed,pedal,actual_speed<0.0)
	wheelspin = 0.0
	var target_boost := throttle*smoothstep(.24,.67,rpm/redline)
	turbo_pressure = move_toward(turbo_pressure,target_boost,maxf(0.0,delta)/maxf(.1,float(spec.spool_seconds)))

func snapshot() -> Dictionary:
	return {"rpm":rpm,"redline":redline,"ideal_shift_rpm":ideal_shift_rpm,"speed_mps":speed_mps,"distance_m":distance_m,"gear":gear,"nitro":nitro,"nitro_active":nitro_active,"wheelspin":wheelspin,"turbo_pressure":turbo_pressure,"limiter":limiter,"last_shift":last_shift,"launch_quality":launch_quality,"launch_score":launch_score,"shift_torque_factor":shift_torque_factor}
