extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Atlas Crew: picape grande cabine dupla, longa e larga, com caçamba aberta.

func build() -> void:
	vehicle_id = "atlas_crew_pickup"
	paint = mat("paint", "526979", 0.32, 0.28)
	var trim := mat("trim", "20272c", 0.22, 0.62)
	var bed := mat("bed_liner", "252b2e", 0.05, 0.90)
	var glass := mat("glass", "203844", 0.36, 0.14)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "e8f5ff", 0.10, 0.14, 0.72)
	var tail := mat("taillight", "c92e2d", 0.10, 0.20, 0.66)
	var chrome := mat("chrome", "c7ced1", 0.76, 0.25)
	set_silhouette("wide_premium_crew_pickup", "four_door_open_bed")

	var axles: Array[float] = [-1.67, 1.74]
	sculpted_shell([
		Vector3(-2.84, 0.72, 0.72), Vector3(-2.50, 1.03, 0.98),
		Vector3(-1.32, 1.10, 1.10), Vector3(0.92, 1.10, 1.08),
		Vector3(2.52, 1.06, 0.98), Vector3(2.82, 0.84, 0.78),
	], axles, 0.43, 0.41, 0.05, 0.30)
	add_underbody(5.34, 1.96, 0.29)
	add_greenhouse(-1.48, 0.86, -1.04, 0.56, 1.06, 1.76, 1.00, 0.82, 2, 0.05)
	add_aero_mirrors(-1.26, 1.25, 1.22, Vector3(0.25, 0.15, 0.16))
	add_flush_handles([-0.72, 0.20], 1.11, 0.91, chrome)

	# Caçamba longa e claramente vazada na câmera superior.
	box(Vector3(0.0, 0.72, 1.80), Vector3(1.76, 0.05, 1.66), bed)
	for side in [-1.0, 1.0]:
		box(Vector3(side * 1.01, 1.01, 1.80), Vector3(0.15, 0.40, 1.72), paint)
		box(Vector3(side * 0.91, 1.18, 1.80), Vector3(0.05, 0.08, 1.67), trim)
		box(Vector3(side * 0.70, 0.82, -2.79), Vector3(0.42, 0.18, 0.04), head)
		box(Vector3(side * 0.96, 0.84, 2.77), Vector3(0.11, 0.34, 0.04), tail)
		for axle in axles:
			add_wheel(side * 0.94, 0.43, axle, 0.41, 0.27, 0.28, 6, "c7ced1")
	box(Vector3(0.0, 0.90, 2.78), Vector3(1.82, 0.42, 0.06), paint)
	box(Vector3(0.0, 0.42, -2.85), Vector3(2.02, 0.15, 0.16), trim)
	box(Vector3(0.0, 0.42, 2.85), Vector3(1.96, 0.14, 0.15), chrome)

