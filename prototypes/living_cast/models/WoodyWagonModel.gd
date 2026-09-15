extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Maré Woody: true long-roof wagon with structural timber panels and a 3D board.


func build() -> void:
	vehicle_id = "surf_woody_wagon"
	paint = mat("paint", "2d8f84", 0.20, 0.32)
	var rubber := mat("rubber", "171b1d", 0.0, 0.92)
	var trim := mat("trim", "2b3032", 0.20, 0.48)
	var glass := mat("glass", "294b58", 0.32, 0.16)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "fff3cf", 0.10, 0.18, 0.62)
	var tail := mat("taillight", "c93b31", 0.10, 0.22, 0.62)
	var wood := mat("wood", "9a5c31", 0.05, 0.58)
	var wood_light := mat("wood_light", "d09a58", 0.04, 0.50)
	var chrome := mat("chrome", "d3d8d9", 0.78, 0.24)
	var board := mat("surfboard", "f4d35e", 0.08, 0.28)
	set_silhouette("long_roof_wood_wagon", "three_pane_estate")

	var axles: Array[float] = [-1.42, 1.43]
	sculpted_shell([
		Vector3(-2.40, 0.67, 0.61), Vector3(-2.12, 0.88, 0.82),
		Vector3(-1.18, 0.94, 0.88), Vector3(0.75, 0.93, 0.91),
		Vector3(2.15, 0.88, 0.86), Vector3(2.40, 0.70, 0.69),
	], axles, 0.35, 0.35, 0.05, 0.26)
	add_underbody(4.58, 1.64, 0.25)
	add_greenhouse(-1.10, 2.18, -0.58, 2.04, 0.91, 1.52, 0.86, 0.73, 3, 0.055)
	add_aero_mirrors(-0.92, 0.98, 0.98, Vector3(0.19, 0.09, 0.16))
	add_flush_handles([-0.20, 0.86], 0.945, 0.80, chrome)

	# Real framed timber insert spans doors and cargo quarter, changing the side mass.
	for side in [-1.0, 1.0]:
		box(Vector3(side * 0.947, 0.65, 0.62), Vector3(0.030, 0.31, 2.90), wood).set_meta("door_trim", true)
		for z in [-0.70, 0.05, 0.80, 1.55]:
			box(Vector3(side * 0.966, 0.65, z), Vector3(0.020, 0.33, 0.050), wood_light).set_meta("door_trim", true)
		for y in [0.50, 0.80]:
			box(Vector3(side * 0.966, y, 0.62), Vector3(0.020, 0.045, 2.88), wood_light).set_meta("door_trim", true)
		for z in [-1.42, 1.43]:
			add_wheel(side * 0.91, 0.35, z, 0.35, 0.215, 0.22, 8, "e0d5bb")

	# Roof rails and a proper rounded surfboard, held by visible straps.
	for side in [-1.0, 1.0]:
		tube([Vector3(side * 0.57, 1.60, -0.30), Vector3(side * 0.57, 1.60, 1.72)], 0.020, chrome)
	var surf := ell(Vector3(0.0, 1.69, 0.78), Vector3(0.52, 0.075, 2.35), board)
	for z in [0.18, 1.30]:
		box(Vector3(0.0, 1.735, z), Vector3(1.24, 0.020, 0.055), trim)
	# Small fin gives the board an unmistakable three-dimensional profile.
	surface([Vector3(-0.04, 1.72, 1.78), Vector3(0.04, 1.72, 1.78), Vector3(0.0, 1.94, 1.52)], board)

	add_lamp_pair(-2.39, 2.39, 0.65, Vector2(0.34, 0.14))
	for z in [-2.43, 2.43]:
		box(Vector3(0.0, 0.39, z), Vector3(1.75, 0.12, 0.12), chrome)
	add_exhaust_dual(0.58, 0.27, 2.43, 0.040)

