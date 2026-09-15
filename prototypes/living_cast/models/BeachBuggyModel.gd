extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Tropic: rounded fiberglass beach tub, short wheelbase and open cabin.


func build() -> void:
	vehicle_id = "beach_buggy"
	paint = mat("paint", "ef6c4d", 0.18, 0.28)
	var rubber := mat("rubber", "171a1d", 0.0, 0.94)
	var trim := mat("trim", "343b3d", 0.25, 0.48)
	var glass := mat("glass", "55a6b0", 0.24, 0.12)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "fff0c4", 0.10, 0.16, 0.72)
	var tail := mat("taillight", "cf3430", 0.10, 0.20, 0.68)
	var ivory := mat("ivory", "f4e4bb", 0.10, 0.40)
	var seat := mat("seat", "e8d2ad", 0.05, 0.72)
	set_silhouette("rounded_fiberglass_tub", "open_short_cabin")

	var axles: Array[float] = [-1.04, 0.94]
	sculpted_shell([
		Vector3(-1.75, 0.49, 0.49), Vector3(-1.48, 0.72, 0.66),
		Vector3(-0.62, 0.82, 0.76), Vector3(0.62, 0.82, 0.76),
		Vector3(1.48, 0.66, 0.62), Vector3(1.68, 0.45, 0.49),
	], axles, 0.39, 0.36, 0.11, 0.24)
	add_underbody(3.05, 1.28, 0.23)

	# Scalloped open cockpit and low framed windshield.
	ell(Vector3(0.0, 0.71, 0.10), Vector3(1.08, 0.20, 1.35), trim)
	for side in [-1.0, 1.0]:
		ell(Vector3(side * 0.28, 0.80, 0.18), Vector3(0.40, 0.34, 0.56), seat)
		box(Vector3(side * 0.28, 0.98, 0.42), Vector3(0.32, 0.44, 0.12), seat)
	surface([
		Vector3(-0.58, 0.73, -0.62), Vector3(0.58, 0.73, -0.62),
		Vector3(0.48, 1.13, -0.43), Vector3(-0.48, 1.13, -0.43),
	], glass)
	tube([Vector3(-0.59, 0.72, -0.63), Vector3(-0.48, 1.14, -0.43), Vector3(0.48, 1.14, -0.43), Vector3(0.59, 0.72, -0.63)], 0.026, ivory)
	# Single polished rollover hoop rather than the dune racer's full cage.
	for side in [-1.0, 1.0]:
		tube([Vector3(side * 0.44, 0.66, 0.68), Vector3(side * 0.42, 1.32, 0.62)], 0.032, ivory)
	tube([Vector3(-0.42, 1.32, 0.62), Vector3(0.42, 1.32, 0.62)], 0.032, ivory)

	for side in [-1.0, 1.0]:
		var lamp := cylinder(Vector3(side * 0.48, 0.73, -1.60), 0.12, 0.07, head)
		lamp.rotation.x = PI / 2.0
		var rear_lamp := cylinder(Vector3(side * 0.51, 0.63, 1.56), 0.09, 0.045, tail)
		rear_lamp.rotation.x = PI / 2.0
		# Rounded separate fenders retain the classic beach-buggy read.
		for axle in axles:
			ell(Vector3(side * 0.77, 0.48, axle), Vector3(0.23, 0.24, 0.80), paint)
	add_axles(axles, 0.82, 0.39, 0.36, 0.23, 0.22, 5, "ece0bd")

