extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Sertão Trail: picape média 4x4, cabine dupla curta e postura robusta.

func build() -> void:
	vehicle_id = "sertao_trail_pickup"
	paint = mat("paint", "8b5941", 0.27, 0.34)
	var trim := mat("trim", "252a2c", 0.18, 0.68)
	var bed := mat("bed_liner", "202527", 0.04, 0.92)
	var glass := mat("glass", "29414b", 0.32, 0.16)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "edf7ff", 0.08, 0.16, 0.68)
	var tail := mat("taillight", "d13a32", 0.08, 0.22, 0.64)
	var alloy := mat("alloy", "929b9f", 0.68, 0.32)
	set_silhouette("midsize_high_belt_pickup", "compact_crew_open_bed")

	var axles: Array[float] = [-1.48, 1.56]
	sculpted_shell([
		Vector3(-2.55, 0.64, 0.68), Vector3(-2.24, 0.96, 0.94),
		Vector3(-1.04, 1.02, 1.04), Vector3(0.78, 1.01, 1.02),
		Vector3(2.26, 0.98, 0.93), Vector3(2.52, 0.74, 0.72),
	], axles, 0.43, 0.40, 0.055, 0.30)
	add_underbody(4.78, 1.82, 0.29)
	add_greenhouse(-1.30, 0.70, -0.92, 0.44, 1.02, 1.68, 0.92, 0.75, 2, 0.05)
	add_aero_mirrors(-1.10, 1.13, 1.16, Vector3(0.24, 0.15, 0.16))
	add_flush_handles([-0.60, 0.18], 1.025, 0.87, alloy)

	box(Vector3(0.0, 0.69, 1.57), Vector3(1.60, 0.05, 1.48), bed)
	for side in [-1.0, 1.0]:
		box(Vector3(side * 0.93, 0.96, 1.57), Vector3(0.14, 0.40, 1.55), paint)
		box(Vector3(side * 0.84, 1.13, 1.57), Vector3(0.045, 0.08, 1.50), trim)
		box(Vector3(side * 0.65, 0.78, -2.49), Vector3(0.38, 0.17, 0.04), head)
		box(Vector3(side * 0.88, 0.80, 2.47), Vector3(0.10, 0.32, 0.04), tail)
		for axle in axles:
			add_wheel(side * 0.88, 0.43, axle, 0.40, 0.26, 0.27, 6, "929b9f")
	# Estribos, para-choques curtos e santo-antônio baixo.
	for side in [-1.0, 1.0]:
		box(Vector3(side * 0.98, 0.40, 0.05), Vector3(0.08, 0.08, 2.36), trim)
		tube([Vector3(side * 0.76, 1.03, 0.82), Vector3(side * 0.72, 1.43, 0.88)], 0.03, trim)
	tube([Vector3(-0.72, 1.43, 0.88), Vector3(0.72, 1.43, 0.88)], 0.03, trim)
	box(Vector3(0.0, 0.86, 2.49), Vector3(1.68, 0.40, 0.06), paint)
	box(Vector3(0.0, 0.41, -2.56), Vector3(1.90, 0.15, 0.15), trim)
	box(Vector3(0.0, 0.41, 2.56), Vector3(1.84, 0.14, 0.15), trim)

