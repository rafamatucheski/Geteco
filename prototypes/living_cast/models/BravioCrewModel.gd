extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Bravio: full four-door crew cab and short open bed, distinct from Ranch Single.


func build() -> void:
	vehicle_id = "bravio_crew"
	paint = mat("paint", "3d6f63", 0.30, 0.31)
	var rubber := mat("rubber", "171b1d", 0.0, 0.94)
	var trim := mat("trim", "293033", 0.24, 0.58)
	var glass := mat("glass", "254653", 0.34, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "e3f4ff", 0.10, 0.16, 0.72)
	var tail := mat("taillight", "cb352f", 0.10, 0.22, 0.68)
	var alloy := mat("alloy", "aeb9bd", 0.74, 0.30)
	var bed := mat("bed_liner", "22292c", 0.06, 0.86)
	var amber := mat("amber", "ee9f2d", 0.10, 0.24, 0.42)
	set_silhouette("crew_cab_short_open_bed", "four_door_pickup")

	var axles: Array[float] = [-1.62, 1.78]
	sculpted_shell([
		Vector3(-2.78, 0.63, 0.70), Vector3(-2.48, 1.00, 0.99),
		Vector3(-1.18, 1.08, 1.08), Vector3(0.95, 1.07, 1.06),
		Vector3(2.58, 1.02, 0.96), Vector3(2.78, 0.79, 0.76),
	], axles, 0.46, 0.43, 0.055, 0.31)
	add_underbody(5.30, 1.92, 0.30)
	add_greenhouse(-1.45, 0.98, -1.02, 0.67, 1.08, 1.78, 0.99, 0.80, 2, 0.055)
	add_aero_mirrors(-1.23, 1.23, 1.22, Vector3(0.26, 0.17, 0.15))
	add_flush_handles([-0.72, 0.25], 1.085, 0.92, alloy)

	# A dark recessed bed visibly breaks the roof/cab mass in top view.
	box(Vector3(0.0, 1.02, 1.88), Vector3(1.72, 0.045, 1.36), bed)
	box(Vector3(0.0, 0.77, 1.88), Vector3(1.60, 0.05, 1.22), bed)
	for side in [-1.0, 1.0]:
		box(Vector3(side * 0.96, 1.13, 1.88), Vector3(0.16, 0.30, 1.55), paint)
		box(Vector3(side * 0.87, 1.18, 1.88), Vector3(0.035, 0.12, 1.42), trim)
		for axle in axles:
			add_wheel(side * 1.05, 0.46, axle, 0.43, 0.275, 0.28, 6, "b5bec2")
		box(Vector3(side * 0.69, 0.83, -2.77), Vector3(0.40, 0.17, 0.040), head)
		box(Vector3(side * 0.98, 0.77, -2.75), Vector3(0.08, 0.17, 0.040), amber)
		box(Vector3(side * 0.89, 0.89, 2.77), Vector3(0.16, 0.35, 0.040), tail)
		box(Vector3(side * 1.06, 0.48, 0.02), Vector3(0.055, 0.09, 2.54), trim)
	# Cab/bed protection hoop and tailgate stamping.
	for side in [-1.0, 1.0]:
		tube([Vector3(side * 0.84, 1.06, 1.03), Vector3(side * 0.78, 1.54, 1.07)], 0.035, trim)
	tube([Vector3(-0.78, 1.54, 1.07), Vector3(0.78, 1.54, 1.07)], 0.035, trim)
	box(Vector3(0.0, 0.88, 2.79), Vector3(1.76, 0.38, 0.055), paint)
	box(Vector3(0.0, 0.87, 2.825), Vector3(0.70, 0.05, 0.020), alloy)
	for z in [-2.82, 2.84]:
		box(Vector3(0.0, 0.40, z), Vector3(2.00, 0.13, 0.14), trim)

