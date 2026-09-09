extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"
## Short expedition cabin, vertical grille, canvas rear, spare and fuel cans.
## Body panels share the inherited paint material for garage recoloring.
func build() -> void:
	paint = mat("paint","dce3df",0.25,0.42)
	var trim := mat("trim","253139",0.25,0.8)
	var canvas := mat("canvas","536358",0.0,0.95)
	var glass := mat("glass","42616c",0.3,0.18)
	var steel := mat("steel","78898c",0.75,0.32)
	var lamp := mat("headlight","fff1c5",0.1,0.2,0.7)
	box(Vector3(0,0.40,0),Vector3(1.8,0.18,4.4),trim)
	box(Vector3(0,0.80,0),Vector3(1.88,0.55,4.35),paint)
	box(Vector3(0,1.12,-1.38),Vector3(1.7,0.14,1.50),paint)
	box(Vector3(0,1.48,-0.61),Vector3(1.65,0.62,0.07),glass)
	box(Vector3(0,1.81,0.57),Vector3(1.82,0.10,2.64),canvas)
	box(Vector3(0,1.47,1.82),Vector3(1.76,0.68,0.14),canvas)
	for side in [-1.0,1.0]:
		box(Vector3(side*0.86,1.46,0.25),Vector3(0.05,0.56,1.60),glass)
		box(Vector3(side*0.90,1.02,0.30),Vector3(0.06,0.40,1.55),paint)
		box(Vector3(side*0.90,1.40,-0.58),Vector3(0.10,0.74,0.10),paint)
		box(Vector3(side*0.90,1.44,1.30),Vector3(0.10,0.70,0.10),canvas)
		box(Vector3(side*1.01,1.34,-0.52),Vector3(0.20,0.18,0.12),trim)
		box(Vector3(side*0.97,0.72,-1.45),Vector3(0.20,0.18,0.96),trim)
		box(Vector3(side*0.97,0.72,1.45),Vector3(0.20,0.18,0.96),trim)
		for z in [-1.45,1.45]: add_wheel(side*0.98,0.36,z,0.38,0.27,0.21,6)
		var lens := cylinder(Vector3(side*0.65,0.96,-2.19),0.15,0.04,lamp)
		lens.rotation.x = PI*0.5
		box(Vector3(side*0.76,0.86,2.2),Vector3(0.19,0.23,0.06),mat("rear_lens","c74b43",0.1,0.2,0.5))
	for x in [-0.36,-0.24,-0.12,0.0,0.12,0.24,0.36]:
		box(Vector3(x,0.96,-2.2),Vector3(0.055,0.34,0.04),trim)
	box(Vector3(0,0.58,-2.27),Vector3(1.94,0.18,0.20),steel)
	box(Vector3(0,0.60,2.25),Vector3(1.94,0.16,0.16),steel)
	var spare := cylinder(Vector3(0,1.18,2.30),0.39,0.23,trim)
	spare.rotation.x = PI*0.5
	box(Vector3(-0.64,1.09,2.31),Vector3(0.29,0.52,0.22),canvas)
	box(Vector3(0.64,1.09,2.31),Vector3(0.29,0.52,0.22),canvas)
	tube([Vector3(0.86,1,-1.4),Vector3(0.86,1.90,-0.57)],0.035,trim)
