extends RefCounted
## Dirigibilidade da V1 (`characters/PlayerCar.gd._physics_process` +
## `cars/VehicleMotionSafety.gd`, `VehicleDrivetrain.gd`, `VehicleLaunchControl.gd`
## e `audio/VehicleEngineSound.drive_force`), portada para o `Vehicle` 3D da V2.
##
## A V2 só lia `max_speed` e `acceleration` (esta /160) do catálogo e aplicava a
## todos o mesmo volante (0,48 rad), o mesmo freio e aderência total: um caminhão
## virava como um cupê e nenhum carro escorregava. Os números do catálogo são os
## da V1 (conferido campo a campo); o que faltava era a física que os consome.
##
## As contas ficam nas unidades da V1 (px, px/s; 16 px = 1 m) para os valores
## do catálogo valerem sem reescala. Plano do chão: 2D (x, y) = 3D (x, z).
## Rumo 2D θ: frente = (cos θ, sin θ); no Vehicle a frente é -basis.z, então
## θ = atan2(-cos yaw, -sin yaw) e dθ = -dyaw.
##
## Só vale com o jogador ao volante. Tráfego e motoristas da polícia
## (`external_input`) continuam no controle simples da V2, calibrado para a IA.
const PX := 16.0
const FRICTION := 600.0

var max_speed := 600.0
var acceleration := 1200.0
var braking := 1500.0
var turn_speed := 3.5
var drift_factor := 0.9
var mass := 0.85
var drivetrain := "rwd"

var yaw_rate := 0.0
var handbrake_slide := 0.0
var lateral_speed := 0.0
# Tração (VehicleDrivetrain).
var force_scale := 1.0
var steer_scale := 1.0
var drift_bias := 0.0
# Largada (VehicleLaunchControl): freio de mão + acelerador parado, soltar o freio.
var launch_holding := false
var launch_charge := 0.0
var launch_release := 0.0
var launch_strength := 0.0
var launch_force := 1.0
var wheelspin := 0.0

func configure(spec: Dictionary) -> void:
	max_speed = float(spec.get("max_speed", 600.0))
	acceleration = float(spec.get("acceleration", 1200.0))
	braking = float(spec.get("braking", 1500.0))
	turn_speed = float(spec.get("turn_speed", 3.5))
	drift_factor = float(spec.get("drift_factor", 0.9))
	mass = float(spec.get("mass", 0.85))
	drivetrain = str(spec.get("drivetrain", "rwd"))

func reset() -> void:
	yaw_rate = 0.0
	handbrake_slide = 0.0
	lateral_speed = 0.0
	launch_holding = false
	launch_charge = 0.0
	launch_release = 0.0
	launch_force = 1.0
	wheelspin = 0.0

## Um passo de física. `throttle` e `turn` como na V1 (turn > 0 = direita).
## Escreve `horizontal_velocity`, `speed` e o yaw do carro.
func step(car: CharacterBody3D, delta: float, throttle: float, turn: float, handbrake: bool, wetness: float) -> void:
	var yaw: float = car.rotation.y
	var heading := atan2(-cos(yaw), -sin(yaw))
	var hv: Vector3 = car.horizontal_velocity
	var velocity := Vector2(hv.x, hv.z) * PX
	var forward := Vector2.from_angle(heading)
	var longitudinal := velocity.dot(forward)

	_update_launch(delta, velocity.length(), throttle, handbrake)
	handbrake_slide = 0.7 if handbrake and velocity.length() > 55.0 else maxf(0.0, handbrake_slide - delta)
	lateral_speed = absf(velocity.dot(forward.orthogonal()))
	_update_drivetrain(longitudinal, throttle, turn, wetness)
	velocity = _grip(velocity, heading, drift_factor + drift_bias, delta, wetness, handbrake_slide > 0.0)
	if handbrake: velocity = velocity.move_toward(Vector2.ZERO, braking * 0.10 * _brake_mass() * delta)

	# Volante: taxa de giro com inércia e raio dependentes da velocidade e massa.
	var slide_steer := lerpf(1.0, 1.65, clampf(handbrake_slide / 0.35, 0.0, 1.0))
	yaw_rate = _steering_rate(yaw_rate, turn, velocity.dot(forward), turn_speed * steer_scale * slide_steer, delta)
	var next_yaw := yaw - yaw_rate * delta
	if absf(yaw_rate) > 0.0001 and car.can_rotate(next_yaw):
		car.rotation.y = next_yaw
		heading = atan2(-cos(next_yaw), -sin(next_yaw))
		forward = Vector2.from_angle(heading)

	if throttle != 0.0:
		var along := velocity.dot(forward)
		if (throttle > 0.0 and along < -10.0) or (throttle < 0.0 and along > 10.0):
			velocity = velocity.move_toward(Vector2.ZERO, braking * _brake_mass() * delta)
		else:
			velocity += forward * throttle * acceleration * _drive_mass() * force_scale * launch_force * _drive_force(velocity.length()) * delta
			velocity = velocity.limit_length(max_speed * 0.8)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * pow(clampf(mass, 0.5, 8.0), -0.65) * delta)
	if launch_holding: velocity = Vector2.ZERO

	car.horizontal_velocity = Vector3(velocity.x, 0.0, velocity.y) / PX
	car.speed = velocity.dot(forward) / PX

## Freio de serviço como a V1: pedal contrário ao movimento ou freio de mão.
func service_brake(car: CharacterBody3D, throttle: float, handbrake: bool) -> bool:
	return handbrake or (throttle != 0.0 and signf(throttle) != signf(car.speed))

func _drive_mass() -> float:
	return pow(clampf(mass, 0.5, 8.0), -0.42)

func _brake_mass() -> float:
	return pow(clampf(mass, 0.5, 8.0), -0.30)

## VehicleEngineSound.drive_force sem a troca de marcha (ela só modula ~0,1 s).
func _drive_force(speed: float) -> float:
	var ratio := clampf(speed / maxf(max_speed * 0.8, 1.0), 0.0, 1.0)
	return 0.26 * (1.0 - ratio * ratio) * (1.0 - 0.55 * ratio) + 0.010

func _steering_rate(previous: float, input: float, speed: float, turn: float, delta: float) -> float:
	var weight := clampf(mass, 0.5, 8.0)
	var response := 11.0 / pow(weight, 0.65)
	var high_speed := 1.0 / (1.0 + pow(absf(speed) / 320.0, 2.0) * pow(weight, 0.4))
	var target := input * turn * clampf(speed / 150.0, -1.0, 1.0) * high_speed
	if absf(speed) < 2.0: return 0.0
	return lerpf(previous, target, 1.0 - exp(-response * maxf(delta, 0.0)))

func _grip(velocity: Vector2, heading: float, drift: float, delta: float, wetness: float, handbrake: bool) -> Vector2:
	if not velocity.is_finite(): return Vector2.ZERO
	var forward := Vector2.from_angle(heading)
	var lateral := forward.orthogonal()
	var damping := lerpf(12.0, 4.0, clampf((drift - 0.7) / 0.5, 0.0, 1.0))
	damping /= pow(clampf(mass, 0.5, 8.0), 0.35)
	damping *= lerpf(1.0, 0.65, clampf(wetness, 0.0, 1.0))
	if handbrake: damping *= 0.22
	return forward * velocity.dot(forward) + lateral * velocity.dot(lateral) * exp(-damping * maxf(0.0, delta))

func _update_drivetrain(longitudinal: float, throttle: float, steering: float, wetness: float) -> void:
	force_scale = 1.0
	steer_scale = 1.0
	drift_bias = 0.0
	var power := absf(throttle) if throttle * longitudinal >= -8.0 else 0.0
	var wet := clampf(wetness, 0.0, 1.0)
	var corner := absf(steering) * clampf(absf(longitudinal) / 160.0, 0.0, 1.0)
	var launch := 1.0 - clampf(absf(longitudinal) / 260.0, 0.0, 1.0)
	match drivetrain:
		"fwd":
			force_scale = 1.0 - power * (0.10 * launch + 0.18 * wet + 0.10 * corner)
			steer_scale = 1.0 - power * corner * lerpf(0.24, 0.40, wet)
			drift_bias = -0.06 * power
		"rwd":
			force_scale = 1.0 - power * (0.06 * launch + 0.24 * wet + 0.08 * corner)
			steer_scale = 1.0 + power * corner * lerpf(0.18, 0.30, wet)
			drift_bias = power * corner * lerpf(0.18, 0.30, wet)
		"4x4":
			force_scale = 1.0 - power * (0.02 * launch + 0.06 * wet)
			steer_scale = 1.0 - corner * 0.16
			drift_bias = -0.08
		"awd":
			force_scale = 1.0 - power * (0.01 * launch + 0.04 * wet + 0.03 * corner)
			steer_scale = 1.0 - power * corner * 0.05
			drift_bias = -0.05 * power

func _update_launch(delta: float, speed: float, throttle: float, brake: bool) -> void:
	launch_strength = clampf((max_speed - 380.0) / 320.0, 0.0, 1.0)
	var was_holding := launch_holding
	launch_holding = brake and throttle > 0.5 and speed < 12.0
	if launch_holding:
		launch_charge = minf(1.0, launch_charge + delta / 1.25)
		launch_release = 0.0
	elif was_holding:
		launch_release = launch_charge * 0.85 if throttle > 0.5 and not brake else 0.0
		launch_charge = 0.0
	else:
		launch_release = maxf(0.0, launch_release - delta)
	if throttle <= 0.0 or brake and not launch_holding:
		launch_release = 0.0
	launch_force = 1.0 + launch_strength * 0.50 * launch_release / 0.85
	wheelspin = launch_strength * launch_release / 0.85 if speed < 230.0 else 0.0
