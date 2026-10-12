extends "res://gameplay/v1_handling/V1Handling.gd"
## Retains the existing collision-safe steering and lateral grip. Longitudinal
## force, gear state and nitro are shared with drag instead of a parallel gearbox.
const DRIVETRAIN := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
var drive := DRIVETRAIN.new()
var _configured := false
var _coast_deceleration := 1.8

func configure(specification: Dictionary) -> void:
	super.configure(specification)
	if specification.get("desert_car",false) or specification.get("full_powertrain",false):
		drive.configure(str(specification.id),specification.get("installed_parts",{}))
		# Street engine braking in m/s², gentler for heavier vehicles.
		_coast_deceleration = 1.8 * clampf(pow(clampf(mass, .5, 8.0), -.30), .8, 1.2)
		_configured = true

func step(car: CharacterBody3D, delta: float, throttle: float, turn: float, handbrake: bool, wetness: float) -> void:
	if not _configured or throttle < 0.0 or car.speed < -.05:
		super.step(car,delta,throttle,turn,handbrake,wetness)
		if _configured: drive.synchronize(float(car.speed),absf(throttle) if float(car.speed)*throttle>0.0 else 0.0,float(car.speed)<0.0)
		return
	var prior_speed := maxf(0.0,float(car.speed))
	# Stock handling supplies safe yaw/cornering only. Its friction is replaced by
	# drivetrain coast/rolling resistance along the new heading below.
	super.step(car,delta,0.0,turn,handbrake,wetness)
	# Brakes hold the chassis while the driven tires spin. Keep this street-only;
	# drag staging and its shared force/gear calibration remain independent.
	if handbrake and throttle > .2:
		if car.horizontal_velocity.length_squared() < .75*.75:
			car.horizontal_velocity = Vector3.ZERO
			car.speed = 0.0
		var previous_rpm := drive.rpm
		drive.synchronize(float(car.speed), throttle)
		drive.launched = true
		drive.wheelspin = 0.0 # Ground-aware tire effects own the held squeal.
		wheelspin = car.burnout_strength()
		if wheelspin > 0.0:
			drive.gear = 1
			drive.shift_remaining = 0.0
			drive.rpm = move_toward(previous_rpm, drive.redline*lerpf(.48,.82,wheelspin), drive.redline*delta*1.8)
		return
	if not drive.launched:
		drive.rpm = drive.redline*.50
		drive.launch()
	drive.speed_mps = prior_speed
	var surface := str(car.get_meta("surface_kind","asphalt"))
	if is_instance_valid(car.effects) and is_instance_valid(car.effects.tire_effects):
		var contacts: Array = car.effects.tire_effects.last_contacts
		for contact in contacts:
			if not contact.is_empty(): surface = str(contact.get("kind",surface)); break
	drive.surface_grip = lerpf(1.0,.67,clampf(wetness,0.0,1.0))
	if surface in ["dirt","sand","grass","snow"]: drive.surface_grip *= float(drive.spec.dirt_grip)*.70
	if drive.rpm >= drive.ideal_shift_rpm: drive.shift_up()
	elif drive.rpm < drive.redline*.35 and drive.gear > 1: drive.shift_down()
	var boost := Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0,JOY_BUTTON_A)
	# Limitador de rua: tira a força nos últimos 8% e não deixa passar do teto.
	var cap := float(drive.spec.street_cap_mps)
	drive.step(delta,throttle*clampf((cap-drive.speed_mps)/(cap*.08),0.0,1.0),boost,1.0 if handbrake else 0.0)
	# Use the driver's pedal, not the limiter's reduced throttle. Rolling/air
	# resistance alone lets street cars coast almost indefinitely. Keep this
	# street response outside the shared drag-race drivetrain calibration.
	if throttle <= .01:
		drive.speed_mps = move_toward(drive.speed_mps, 0.0, _coast_deceleration * clampf(delta, 0.0, .25))
	drive.speed_mps = minf(drive.speed_mps,cap)
	var forward: Vector3 = -car.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var lateral: Vector3 = car.horizontal_velocity-forward*car.horizontal_velocity.dot(forward)
	car.horizontal_velocity = lateral+forward*drive.speed_mps
	car.speed = drive.speed_mps
	wheelspin = drive.wheelspin

func reset() -> void:
	super.reset()
	drive.reset()
