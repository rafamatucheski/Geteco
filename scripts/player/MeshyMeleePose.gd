extends RefCounted
## Key poses for the imported skeleton: hands stay in front of the jacket.
const GRENADE_RELEASE := 0.20

static func sample(id: String, age: float, aiming: bool) -> Dictionary:
	if id == "grenade":
		var ready := Vector3(0.24,0.72,-0.10)
		var cocked := Vector3(0.25,1.18,-0.12)
		var released := Vector3(0.12,1.13,-0.38)
		var follow := Vector3(0.10,0.90,-0.37)
		var hand := ready
		if age < GRENADE_RELEASE:
			hand = cocked.lerp(released,smoothstep(0.0,GRENADE_RELEASE,age))
		elif age < 0.38:
			hand = released.lerp(follow,smoothstep(GRENADE_RELEASE,0.38,age))
		elif age < 0.70:
			hand = follow.lerp(ready,smoothstep(0.38,0.70,age))
		return {"hand":hand,"basis":Basis(Vector3.RIGHT,-0.20),"left":Vector3(-0.215,0.65,-0.025)}
	return shoulder_swing(id, age)

# Carry behind the shoulder, join the free hand, then sweep through contact.
# Contact lies inside one continuous interpolation, never at a zero-speed key.
static func shoulder_swing(id: String, age: float, gait_phase: float = 0.0, movement: float = 0.0, running: float = 0.0, body_offset: Vector3 = Vector3.ZERO) -> Dictionary:
	var axe := id == "axe"
	var load_end := 0.18 if axe else 0.14
	var follow_end := 0.38 if axe else 0.34
	var return_start := 0.49 if axe else 0.43
	var end := 0.72 if axe else 0.58
	var carry := Vector3(0.25, 1.10, -0.24)
	var loaded := Vector3(0.19, 1.15, -0.25)
	var follow := Vector3(-0.08, 0.87 if axe else 0.98, -0.37)
	var clear := Vector3(0.27, 1.13, -0.32)
	var roll := -PI/2 if axe else 0.0
	var carry_basis := _basis(Vector3(2.82, -0.10, roll))
	var load_basis := _basis(Vector3(1.75, -0.35, roll)) if axe else _basis(Vector3(0.40, -1.65, 0))
	var follow_basis := _basis(Vector3(-0.65, 0.38, roll)) if axe else _basis(Vector3(0.10, 1.15, 0))
	var clear_basis := _basis(Vector3(1.40, -0.65, roll))
	var hand := carry
	var basis := carry_basis
	var torso := 0.0
	if age < load_end:
		var t := smoothstep(0.0, load_end, age)
		hand = carry.lerp(loaded, t)
		basis = carry_basis.slerp(load_basis, t)
		torso = lerpf(0.0, -0.30, t)
	elif age < follow_end:
		var t := smoothstep(load_end, follow_end, age)
		hand = loaded.lerp(follow, t)
		basis = load_basis.slerp(follow_basis, t)
		torso = lerpf(-0.30, 0.38, t)
	elif age < return_start:
		var t := smoothstep(follow_end, return_start, age)
		hand = follow.lerp(clear, t)
		basis = follow_basis.slerp(clear_basis, t)
		torso = lerpf(0.38, 0.12, t)
	elif age < end:
		var t := smoothstep(return_start, end, age)
		hand = clear.lerp(carry, t)
		basis = clear_basis.slerp(carry_basis, t)
		torso = lerpf(0.12, 0.0, t)
	var support_weight := smoothstep(0.0, load_end * 0.75, age) * (1.0 - smoothstep(follow_end, return_start, age))
	# Rock around the shoulder contact, not around the hand: the shaft keeps
	# its support while the head has a small, weighty response to each step.
	var carry_weight := (1.0 - smoothstep(0.0, load_end, age)) + smoothstep(return_start, end, age)
	var motion := movement * carry_weight
	if motion > 0.0:
		var pitch := sin(gait_phase * 2.0 - 0.35) * lerpf(0.035, 0.065, running)
		var roll_sway := sin(gait_phase) * lerpf(0.015, 0.030, running)
		var yaw := cos(gait_phase) * lerpf(0.018, 0.035, running)
		var sway := _basis(Vector3(pitch, yaw, roll_sway) * motion)
		var shoulder := Vector3(0.23, 1.18, -0.015)
		hand = shoulder + sway * (hand - shoulder) + body_offset * carry_weight
		basis = sway * basis
	return {"hand": hand, "basis": basis, "support_weight": support_weight, "torso": torso}

static func _basis(angles: Vector3) -> Basis:
	return Basis(Vector3.UP,angles.y)*Basis(Vector3.RIGHT,angles.x)*Basis(Vector3.BACK,angles.z)
