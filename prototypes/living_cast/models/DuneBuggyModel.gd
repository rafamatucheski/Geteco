extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Sandstorm: open tubular desert racer with exposed suspension and rear engine.


func build() -> void:
	vehicle_id = "dune_buggy"
	paint = mat("paint", "e9a326", 0.24, 0.34)
	var rubber := mat("rubber", "16191b", 0.0, 0.94)
	var trim := mat("trim", "252b2f", 0.25, 0.48)
	var glass := mat("glass", "36515d", 0.32, 0.18)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "e8f5ff", 0.12, 0.16, 0.72)
	var tail := mat("taillight", "d83a30", 0.10, 0.22, 0.72)
	var alloy := mat("alloy", "b8bec2", 0.78, 0.30)
	var seat := mat("seat", "2b2520", 0.05, 0.82)
	var engine := mat("engine", "666e72", 0.72, 0.42)
	set_silhouette("open_tube_long_travel", "open_two_seat")

	var axles: Array[float] = [-1.03, 0.93]
	sculpted_shell([
		Vector3(-1.70, 0.42, 0.47), Vector3(-1.42, 0.64, 0.59),
		Vector3(-0.45, 0.69, 0.69), Vector3(0.72, 0.62, 0.65),
		Vector3(1.48, 0.45, 0.50),
	], axles, 0.42, 0.40, 0.07, 0.26)
	add_underbody(2.80, 0.92, 0.26)

	# Open cockpit, two buckets and a small wind deflector.
	box(Vector3(0.0, 0.72, -0.05), Vector3(1.05, 0.05, 1.14), trim)
	for side in [-1.0, 1.0]:
		ell(Vector3(side * 0.29, 0.79, 0.12), Vector3(0.42, 0.38, 0.58), seat)
		box(Vector3(side * 0.29, 0.97, 0.38), Vector3(0.32, 0.48, 0.14), seat)
	surface([
		Vector3(-0.50, 0.72, -0.58), Vector3(0.50, 0.72, -0.58),
		Vector3(0.42, 1.02, -0.43), Vector3(-0.42, 1.02, -0.43),
	], glass)

	# Full cage and long-travel suspension make the silhouette unmistakable.
	for side in [-1.0, 1.0]:
		tube([Vector3(side * 0.56, 0.55, -0.68), Vector3(side * 0.48, 1.38, -0.20), Vector3(side * 0.46, 1.38, 0.62), Vector3(side * 0.55, 0.57, 1.00)], 0.035, trim)
		tube([Vector3(side * 0.48, 1.38, -0.20), Vector3(-side * 0.46, 1.38, 0.62)], 0.026, trim)
		for axle in axles:
			tube([Vector3(side * 0.56, 0.37, axle), Vector3(side * 0.83, 0.42, axle)], 0.022, alloy)
	tube([Vector3(-0.48, 1.38, -0.20), Vector3(0.48, 1.38, -0.20)], 0.034, trim)
	tube([Vector3(-0.46, 1.38, 0.62), Vector3(0.46, 1.38, 0.62)], 0.034, trim)

	# Exposed rear engine and high exhaust.
	box(Vector3(0.0, 0.70, 1.08), Vector3(0.78, 0.48, 0.58), engine)
	for side in [-1.0, 1.0]:
		var intake := cylinder(Vector3(side * 0.25, 1.03, 1.08), 0.085, 0.24, trim)
		intake.rotation.x = PI / 2.0
		var lamp := cylinder(Vector3(side * 0.42, 0.72, -1.57), 0.105, 0.07, head)
		lamp.rotation.x = PI / 2.0
		box(Vector3(side * 0.38, 0.61, 1.49), Vector3(0.16, 0.10, 0.035), tail)
	add_axles(axles, 0.84, 0.42, 0.40, 0.25, 0.25, 6, "c0c5c8")
