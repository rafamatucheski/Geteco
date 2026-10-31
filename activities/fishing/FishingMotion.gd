extends RefCounted
## Alvos de mão escritos usam o IK existente do Dante e mantêm os pés físicos.
static func pose(phase: String, phase_time: float, charge: float, tension: float, held: bool, age: float) -> Dictionary:
	var right := Vector3(.17, 1.02, -.33)
	var left := Vector3(-.02, .98, -.43)
	var lean := -.025
	var yaw := 0.0
	var pitch := .48
	match phase:
		"charging":
			var preparation := smoothstep(0.0, 1.0, charge)
			right = right.lerp(Vector3(.25, 1.46, .02), preparation)
			left = left.lerp(Vector3(-.01, 1.30, -.10), preparation)
			pitch = lerpf(.48, 1.82, preparation)
			lean = lerpf(-.025, -.10, preparation)
			yaw = -.16 * preparation
		"casting":
			var cast := smoothstep(0.0, .72, phase_time)
			var prepared := smoothstep(0.0, 1.0, charge)
			right = right.lerp(Vector3(.25, 1.46, .02), prepared).lerp(Vector3(.20, 1.10, -.48), cast)
			left = left.lerp(Vector3(-.01, 1.30, -.10), prepared).lerp(Vector3(-.04, 1.00, -.52), cast)
			pitch = lerpf(lerpf(.48, 1.82, prepared), .30, cast)
			lean = lerpf(lerpf(-.025, -.10, prepared), .08, cast)
			yaw = lerpf(-.16 * prepared, .07, cast)
		"waiting", "bite":
			var breath := sin(age * 1.4) * .008
			right.y += breath
			left.y += breath
			pitch += sin(age * 1.1) * .012
		"hooking":
			var strike := sin(clampf(phase_time / .45, 0.0, 1.0) * PI * .5)
			right = right.lerp(Vector3(.22, 1.42, -.25), strike)
			left = left.lerp(Vector3(-.01, 1.29, -.36), strike)
			pitch = lerpf(.48, 1.16, strike)
			lean = -.12 * strike
		"reeling":
			var lift := .5 + .5 * sin(age * 2.6)
			var settle := 1.0 - smoothstep(0.0, .45, phase_time)
			right = Vector3(.20, 1.08 + tension * .20 + lift * .045, -.30)
			right = right.lerp(Vector3(.22, 1.42, -.25), settle)
			left = right + Vector3(-.22, -.08, -.09)
			if held: left += Vector3(sin(age * 10.0) * .035, cos(age * 10.0) * .035, 0)
			pitch = lerpf(.58 + tension * .36 + lift * .08, 1.16, settle)
			lean = -.04 - tension * .10
		"landing":
			var lift := smoothstep(0.0, 1.0, phase_time / 1.9)
			right = Vector3(.20, 1.25, -.30).lerp(Vector3(.29, 1.38, -.20), lift)
			left = Vector3(-.02, 1.17, -.39).lerp(Vector3(-.20, 1.10, -.49), lift)
			var support := smoothstep(.60, 1.0, phase_time / 1.9)
			right = right.lerp(Vector3(.20, 1.10, -.45), support)
			left = left.lerp(Vector3(-.20, 1.10, -.45), support)
			pitch = lerpf(.86, 1.20, lift)
			lean = lerpf(-.10, .035, lift)
		"caught":
			right = Vector3(.20, 1.10, -.45)
			left = Vector3(-.20, 1.10, -.45)
			pitch = 1.20
			lean = .035
		"releasing":
			var lift := smoothstep(0.0, .55, phase_time)
			var relax := smoothstep(.68, 1.35, phase_time)
			right = Vector3(.20, 1.10, -.45).lerp(Vector3(.20, 1.58, -.53), lift).lerp(Vector3(.23, 1.02, -.28), relax)
			left = Vector3(-.20, 1.10, -.45).lerp(Vector3(-.20, 1.58, -.53), lift).lerp(Vector3(-.23, 1.02, -.28), relax)
			pitch = 1.20
			lean = lerpf(.035, .10, lift) * (1.0 - relax)
		"storing":
			var tuck := smoothstep(0.0, .9, phase_time)
			right = Vector3(.20, 1.10, -.45).lerp(Vector3(-.33, 1.27, .13), tuck)
			left = Vector3(-.20, 1.10, -.45).lerp(Vector3(-.40, .90, .13), tuck)
			pitch = 1.20
			lean = .035
			yaw = -.13 * tuck
	var gripping := phase not in ["caught", "releasing", "storing"]
	return {"right":right, "left":left, "basis":Basis.IDENTITY, "right_grip":gripping,
		"left_grip":gripping, "right_solve":true, "left_solve":true,
		"armed":true, "lean":lean, "torso_yaw":yaw, "support_locked":false,
		"arm_rate":20.0, "pitch":pitch}
