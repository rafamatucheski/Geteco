extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"
## Conventional long-hood rigid truck; negative Z is the front.

func build() -> void:
	paint = mat("paint", "943e32", 0.35, 0.35)
	var steel := mat("frame", "293238", 0.5, 0.6)
	var chrome := mat("chrome", "bfcbd0", 0.8, 0.22)
	var glass := mat("glass", "203b49", 0.3, 0.18)
	var head := mat("headlight", "fff0cb", 0.1, 0.2, 0.7)
	var tail := mat("taillight", "db4130", 0.1, 0.3, 0.5)
	var amber := mat("marker", "ffae38", 0.1, 0.3, 0.5)
	box(Vector3(0,0.48,0), Vector3(1.85,0.26,8.0), steel)
	# Separate hood and tall day cab give the American silhouette.
	box(Vector3(0,1.18,-2.95), Vector3(1.48,1.03,1.90), paint)
	box(Vector3(0,1.60,-1.32), Vector3(2.08,1.95,1.42), paint)
	box(Vector3(0,2.02,-2.04), Vector3(1.85,0.68,0.04), glass)
	box(Vector3(0,2.62,-1.42), Vector3(2.22,0.12,1.64), paint)
	box(Vector3(0,1.18,-3.92), Vector3(1.42,1.05,0.12), chrome)
	box(Vector3(0,1.18,-4.0), Vector3(1.16,0.83,0.03), steel)
	for x in 9:
		box(Vector3(-0.52+x*0.13,1.18,-4.03), Vector3(0.035,0.82,0.025), chrome)
	box(Vector3(0,0.58,-4.06), Vector3(2.42,0.30,0.20), chrome)
	for side in [-1.0,1.0]:
		box(Vector3(side*1.04,2.03,-1.37), Vector3(0.035,0.64,1.02), glass)
		box(Vector3(side*1.10,0.72,-1.48), Vector3(0.35,0.16,1.22), chrome)
		box(Vector3(side*0.97,1.03,-3.06), Vector3(0.52,0.22,1.65), paint)
		box(Vector3(side*0.97,1.04,-3.92), Vector3(0.38,0.26,0.06), head)
		box(Vector3(side*1.27,2.10,-1.95), Vector3(0.18,0.36,0.16), chrome)
		tube([Vector3(side*1.02,2.14,-1.85),Vector3(side*1.28,2.14,-1.95)],0.025,chrome)
		cylinder(Vector3(side*1.03,1.88,-0.48),0.085,2.55,chrome)
		cylinder(Vector3(side*1.03,3.16,-0.48),0.065,0.02,steel)
		var fuel := cylinder(Vector3(side*0.92,0.74,0.24),0.26,1.0,chrome)
		fuel.rotation.x = PI*0.5
		box(Vector3(side*0.91,0.63,3.98),Vector3(0.30,0.18,0.06),tail)
		for z in [-2.95,2.10,3.30]:
			add_wheel(side*1.01,0.49,z,0.49,0.32,0.28,6)
		for z in [0.25,1.65,3.65]:
			box(Vector3(side*1.19,1.01,z),Vector3(0.04,0.09,0.16),amber)
	for x in [-0.78,-0.39,0.0,0.39,0.78]:
		box(Vector3(x,2.71,-2.06),Vector3(0.12,0.08,0.13),amber)
	build_cargo(steel,chrome)

func build_cargo(steel: Material, chrome: Material) -> void:
	box(Vector3(0,0.96,1.72),Vector3(2.40,0.20,4.50),steel)
	var wood := mat("deck", "92724b", 0.0, 0.9)
	for x in 9:
		box(Vector3(-1.04+x*0.26,1.075,1.72),Vector3(0.245,0.05,4.40),wood)
	for side in [-1.0,1.0]:
		for z in [-0.44,1.02,2.48,3.92]:
			box(Vector3(side*1.16,1.38,z),Vector3(0.08,0.72,0.08),chrome)
	box(Vector3(0,1.42,-0.49),Vector3(2.36,0.88,0.10),paint)
