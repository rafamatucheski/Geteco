extends RefCounted
## Empinada manual compartilhada entre motos de rua e de trilha. Ângulos são relativos ao chão;
## o corpo de colisão mantém o apoio no chão e o casco conservador contra obstáculos.
const MIN_SPEED := 2.0
const FULL_SPEED := 7.0
const MAX_PITCH := .62
const RISE_RATE := 1.15
const LOWER_RATE := 1.75
const BRAKE_RATE := 3.8
var pitch := 0.0

func reset() -> void:
	pitch = 0.0

func step(delta: float, requested: bool, eligible: bool, grounded: bool, speed: float, throttle: float, braking: bool) -> void:
	if delta <= 0 or not is_finite(delta): return
	if not eligible or not grounded or not is_finite(speed) or not is_finite(throttle):
		reset()
		return
	var target := 0.0
	if requested and not braking and speed > MIN_SPEED and throttle > .15:
		target = MAX_PITCH * smoothstep(MIN_SPEED, FULL_SPEED, speed) * clampf(throttle,0,1)
	var rate := RISE_RATE if target > pitch else (BRAKE_RATE if braking else LOWER_RATE)
	pitch = move_toward(pitch, target, delta*rate)

func steering_scale() -> float:
	return lerpf(1.0, .45, clampf(pitch/MAX_PITCH,0,1))

static func rear_pivot_offset(angle: float, rear_contact: Vector3) -> Vector3:
	return rear_contact - Basis(Vector3.RIGHT,angle)*rear_contact
