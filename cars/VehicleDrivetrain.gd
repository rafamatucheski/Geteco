extends RefCounted
## Arcade axle traction. These multipliers consume engine force and tire grip;
## they never inject velocity or yaw when the driver is not applying power.
var force_scale: float = 1.0
var steer_scale: float = 1.0
var drift_bias: float = 0.0

func update(kind: String, longitudinal: float, throttle: float, steering: float, wetness: float) -> void:
	force_scale = 1.0
	steer_scale = 1.0
	drift_bias = 0.0
	# Opposite pedal input is service braking, not power oversteer.
	var power := absf(throttle) if throttle * longitudinal >= -8.0 else 0.0
	var wet := clampf(wetness, 0.0, 1.0)
	var corner := absf(steering) * clampf(absf(longitudinal) / 160.0, 0.0, 1.0)
	var launch := 1.0 - clampf(absf(longitudinal) / 260.0, 0.0, 1.0)
	match kind:
		"fwd":
			# Front tires share acceleration and steering: widen under power.
			force_scale = 1.0 - power * (0.10 * launch + 0.18 * wet + 0.10 * corner)
			steer_scale = 1.0 - power * corner * lerpf(0.24, 0.40, wet)
			drift_bias = -0.06 * power
		"rwd":
			# Driven rear axle loses lateral reserve in a powered corner.
			force_scale = 1.0 - power * (0.06 * launch + 0.24 * wet + 0.08 * corner)
			steer_scale = 1.0 + power * corner * lerpf(0.18, 0.30, wet)
			drift_bias = power * corner * lerpf(0.18, 0.30, wet)
		"4x4":
			# Utility four-wheel drive: strong traction, conservative turning.
			force_scale = 1.0 - power * (0.02 * launch + 0.06 * wet)
			steer_scale = 1.0 - corner * 0.16
			drift_bias = -0.08
		"awd":
			# Road AWD preserves traction with less cornering resistance.
			force_scale = 1.0 - power * (0.01 * launch + 0.04 * wet + 0.03 * corner)
			steer_scale = 1.0 - power * corner * 0.05
			drift_bias = -0.05 * power
