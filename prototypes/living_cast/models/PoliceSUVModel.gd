extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"
## Taller five-door patrol body using the same wheel, damage and lightbar contracts.
func build() -> void:
	vehicle_id = "police_suv"
	paint = mat("paint", "e5e9ed", 0.3, 0.35)
	var navy := mat("police_navy", "19314e", 0.3, 0.35)
	var trim := mat("black_trim", "202830", 0.1, 0.75)
	var glass := mat("glass", "172835", 0.25, 0.18)
	var headlight := mat("headlight", "eef4fa", 0.1, 0.15, 0.8)
	var taillight := mat("taillight", "c52b35", 0.1, 0.2, 0.6)
	var grille := mat("grille", "7b8890", 0.7, 0.4)
	box(Vector3(0,0.39,0), Vector3(1.96,0.20,5.10), trim)
	box(Vector3(0,0.83,0), Vector3(2.10,0.66,5.05), paint)
	# Long roof and upright rear hatch distinguish the SUV at gameplay zoom.
	box(Vector3(0,1.78,0.60), Vector3(1.86,0.10,3.75), paint)
	box(Vector3(0,1.18,-1.82), Vector3(1.92,0.08,1.28), navy)
	var windshield := box(Vector3(0,1.48,-1.04),Vector3(1.77,0.60,0.05),glass)
	windshield.rotation.x = deg_to_rad(22)
	box(Vector3(0,1.47,2.47),Vector3(1.78,0.51,0.045),glass)
	for side in [-1.0,1.0]:
		box(Vector3(side*0.932,1.47,0.64),Vector3(0.045,0.51,3.57),glass)
		for pillar_z in [-1.05,0.12,1.33,2.41]:
			box(Vector3(side*0.94,1.46,pillar_z),Vector3(0.075,0.63,0.09),paint)
		box(Vector3(side*1.115,1.24,-0.96),Vector3(0.22,0.18,0.26),trim)
		box(Vector3(side*1.06,0.47,0),Vector3(0.12,0.09,2.65),trim)
		for handle_z in [-0.12,1.12]:
			box(Vector3(side*1.055,1.045,handle_z),Vector3(0.035,0.055,0.21),trim)
		box(Vector3(side*0.77,0.97,-2.55),Vector3(0.40,0.22,0.06),headlight)
		box(Vector3(side*0.93,1.01,2.55),Vector3(0.20,0.40,0.06),taillight)
		for axle in [-1.55,1.55]:
			add_wheel(side*1.01,0.39,axle,0.39,0.25,0.24,6)
	box(Vector3(0,0.58,-2.59),Vector3(2.12,0.23,0.18),trim)
	box(Vector3(0,0.58,2.59),Vector3(2.12,0.23,0.18),trim)
	box(Vector3(0,0.96,-2.55),Vector3(0.92,0.23,0.055),trim)
	for y in [0.89,0.96,1.03]:
		box(Vector3(0,y,-2.585),Vector3(0.87,0.025,0.025),grille)
	box(Vector3(0,0.90,2.55),Vector3(1.45,0.23,0.035),navy)
	add_lightbar(1.88,-0.32,Color("e83c42"),Color("3689ef"),1.22)
