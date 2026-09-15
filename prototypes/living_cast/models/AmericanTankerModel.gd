extends "res://prototypes/living_cast/models/AmericanFlatbedModel.gd"

func build_cargo(steel: Material, chrome: Material) -> void:
	var tank := cylinder(Vector3(0,1.84,1.72),1.08,4.36,chrome)
	tank.rotation.x = PI*0.5
	for z in [-0.05,1.72,3.50]:
		box(Vector3(0,0.99,z),Vector3(2.18,0.22,0.30),steel)
		var band := cylinder(Vector3(0,1.84,z),1.105,0.09,steel)
		band.rotation.x = PI*0.5
	for z in [0.55,2.75]:
		cylinder(Vector3(0,2.95,z),0.26,0.12,steel)
	box(Vector3(0,3.03,1.72),Vector3(0.55,0.06,3.10),steel)
	for x in [-0.32,0.32]:
		tube([Vector3(x,1.12,3.96),Vector3(x,3.10,3.96)],0.025,chrome)
	for rung in 7:
		box(Vector3(0,1.20+rung*0.28,3.97),Vector3(0.68,0.04,0.04),chrome)
