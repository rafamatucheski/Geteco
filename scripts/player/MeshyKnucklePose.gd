extends RefCounted
## Independent closed-fist targets. One hand strikes while the other guards.
const DURATION := 0.32

static func sample(variant: int, age: float, engaged: bool, swing: float, sprint: float) -> Dictionary:
	var right := Vector3(0.14,1.03,-0.25)
	var left := Vector3(-0.14,1.06,-0.25)
	var right_basis := Basis.IDENTITY
	var left_basis := Basis.IDENTITY
	if not engaged and age >= DURATION:
		right = Vector3(0.20,lerpf(0.72,0.88,sprint),-0.10-swing*0.12)
		left = Vector3(-0.20,lerpf(0.72,0.88,sprint),-0.10+swing*0.12)
	elif age < DURATION:
		var reach := smoothstep(0.0,0.12,age)*(1.0-smoothstep(0.14,DURATION,age))
		var turn := reach*PI*0.45
		match posmod(variant,4):
			0:
				left = left.lerp(Vector3(-0.04,1.08,-0.41),reach)
				left_basis = Basis(Vector3.BACK,-turn)
			1:
				right = right.lerp(Vector3(0.035,1.06,-0.41),reach)
				right_basis = Basis(Vector3.BACK,turn)
			2:
				# The hook arcs outward before crossing in front of the chest.
				var opening := sin(clampf(age/0.15,0,1)*PI)*0.10 if age < 0.15 else 0.0
				left = left.lerp(Vector3(0.03,1.055,-0.35),reach)
				left.x -= opening
				left_basis = Basis(Vector3.UP,-0.55*reach)*Basis(Vector3.BACK,-turn)
			3:
				# A short rising arc, with the fist kept ahead of the jacket.
				var load_offset := sin(clampf(age/0.12,0,1)*PI)*0.09 if age < 0.12 else 0.0
				right = right.lerp(Vector3(0.045,1.16,-0.34),reach)
				right.y -= load_offset
				right_basis = Basis(Vector3.RIGHT,-0.45*reach)*Basis(Vector3.BACK,0.35*reach)
	return {"right":right,"left":left,"right_basis":right_basis,"left_basis":left_basis}
