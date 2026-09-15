extends "res://prototypes/living_cast/models/AmericanFlatbedModel.gd"

func build_cargo(steel: Material, chrome: Material) -> void:
	var bed := mat("dump_bed", "bd883c", 0.35, 0.6)
	box(Vector3(0,1.06,1.72),Vector3(2.32,0.22,4.50),steel)
	# Open top, visible floor and reinforcing ribs distinguish the tipper.
	for side in [-1.0,1.0]:
		box(Vector3(side*1.13,1.77,1.72),Vector3(0.14,1.35,4.50),bed)
		box(Vector3(side*1.15,2.47,1.72),Vector3(0.22,0.10,4.60),bed)
		for z in [-0.30,0.72,1.74,2.76,3.78]:
			box(Vector3(side*1.23,1.77,z),Vector3(0.10,1.38,0.12),bed)
	for z in [-0.51,3.94]:
		box(Vector3(0,1.77,z),Vector3(2.32,1.35,0.14),bed)
		for x in [-0.8,0.8]:
			box(Vector3(x,2.40,z),Vector3(0.20,0.15,0.22),chrome)
