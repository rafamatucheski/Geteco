extends RefCounted
## Key poses for the imported skeleton: hands stay in front of the jacket.
const GRENADE_RELEASE := 0.20

static func sample(id: String, age: float, aiming: bool) -> Dictionary:
	if id == "grenade":
		var ready := Vector3(0.23,0.94,-0.27)
		var cocked := Vector3(0.25,1.18,-0.12)
		var released := Vector3(0.12,1.13,-0.38)
		var follow := Vector3(0.10,0.90,-0.37)
		var hand := cocked if aiming else ready
		if age < GRENADE_RELEASE:
			hand = cocked.lerp(released,smoothstep(0.0,GRENADE_RELEASE,age))
		elif age < 0.38:
			hand = released.lerp(follow,smoothstep(GRENADE_RELEASE,0.38,age))
		elif age < 0.70:
			hand = follow.lerp(cocked if aiming else ready,smoothstep(0.38,0.70,age))
		return {"hand":hand,"basis":Basis(Vector3.RIGHT,-0.20),"left":Vector3(-0.22,0.87,-0.22)}
	var times: Array[float]
	var positions: Array[Vector3]
	var angles: Array[Vector3]
	if id == "axe":
		times = [0.0,0.18,0.28,0.40,0.72]
		positions = [Vector3(0.10,0.94,-0.36),Vector3(0.15,1.12,-0.30),Vector3(0.04,0.96,-0.38),Vector3(0.00,0.86,-0.35),Vector3(0.10,0.94,-0.36)]
		angles = [Vector3(0.82,-0.12,-PI/2),Vector3(1.40,-0.12,-PI/2),Vector3(-0.08,0.08,-PI/2),Vector3(-0.45,0.20,-PI/2),Vector3(0.82,-0.12,-PI/2)]
	else:
		times = [0.0,0.14,0.24,0.36,0.58]
		positions = [Vector3(0.0,0.95,-0.32),Vector3(0.13,1.03,-0.28),Vector3(-0.03,0.98,-0.36),Vector3(-0.10,0.90,-0.32),Vector3(0.0,0.95,-0.32)]
		angles = [Vector3(0.95,-0.40,0),Vector3(0.65,-1.25,0),Vector3(0.08,0,0),Vector3(0.12,1.0,0),Vector3(0.95,-0.40,0)]
	var hand := positions[0]
	var basis := _basis(angles[0])
	for i in range(1,times.size()):
		if age >= times[i-1] and age < times[i]:
			var t := smoothstep(times[i-1],times[i],age)
			hand = positions[i-1].lerp(positions[i],t)
			basis = _basis(angles[i-1]).slerp(_basis(angles[i]),t)
			break
	return {"hand":hand,"basis":basis}

static func _basis(angles: Vector3) -> Basis:
	return Basis(Vector3.UP,angles.y)*Basis(Vector3.RIGHT,angles.x)*Basis(Vector3.BACK,angles.z)
