extends RefCounted
## Hold throttle + handbrake at rest, then release the brake to launch.
var holding := false
var charge := 0.0
var release_remaining := 0.0
var strength := 0.0
var force_scale := 1.0
var wheelspin := 0.0

func reset() -> void:
	holding = false
	charge = 0.0
	release_remaining = 0.0
	force_scale = 1.0
	wheelspin = 0.0

func update(delta: float, speed: float, throttle: float, brake: bool, top_speed: float, enabled: bool) -> void:
	if not enabled:
		reset()
		return
	strength = clampf((top_speed - 380.0) / 320.0, 0.0, 1.0)
	var was_holding := holding
	holding = brake and throttle > 0.5 and speed < 12.0
	if holding:
		charge = minf(1.0, charge + delta / 1.25)
		release_remaining = 0.0
	elif was_holding:
		release_remaining = charge * 0.85 if throttle > 0.5 and not brake else 0.0
		charge = 0.0
	else:
		release_remaining = maxf(0.0, release_remaining - delta)
	if throttle <= 0.0 or brake and not holding:
		release_remaining = 0.0
	force_scale = 1.0 + strength * 0.50 * release_remaining / 0.85
	wheelspin = strength * release_remaining / 0.85 if speed < 230.0 else 0.0
