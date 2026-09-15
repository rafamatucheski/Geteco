extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Vale Cross: compact AWD crossover with an arched roof and planted cladding.


func build() -> void:
	vehicle_id = "vale_crossover"
	paint = mat("paint", "8e5b43", 0.28, 0.30)
	var rubber := mat("rubber", "171b1e", 0.0, 0.94)
	var trim := mat("trim", "2a3033", 0.18, 0.62)
	var glass := mat("glass", "284653", 0.34, 0.16)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "e1f5ff", 0.12, 0.16, 0.72)
	var tail := mat("taillight", "cf3531", 0.10, 0.22, 0.70)
	var alloy := mat("alloy", "bbc5c9", 0.76, 0.27)
	var amber := mat("amber", "f0a02b", 0.10, 0.22, 0.40)
	set_silhouette("arched_compact_crossover", "three_pane_fastback_suv")

	var axles: Array[float] = [-1.28, 1.30]
	sculpted_shell([
		Vector3(-2.18, 0.60, 0.68), Vector3(-1.94, 0.91, 0.91),
		Vector3(-0.90, 1.00, 1.03), Vector3(0.92, 0.99, 1.05),
		Vector3(2.00, 0.84, 0.88), Vector3(2.18, 0.58, 0.66),
	], axles, 0.43, 0.40, 0.065, 0.31)
	add_underbody(4.10, 1.72, 0.30)
	add_greenhouse(-1.15, 1.82, -0.66, 1.36, 1.04, 1.70, 0.92, 0.73, 3, 0.085)
	add_aero_mirrors(-0.92, 1.05, 1.10, Vector3(0.21, 0.10, 0.17))
	add_flush_handles([-0.28, 0.75], 1.005, 0.90, alloy)

	# Unpainted protection follows the rocker and wheel shoulders.
	for side in [-1.0, 1.0]:
		box(Vector3(side * 1.005, 0.40, 0.0), Vector3(0.070, 0.14, 2.30), trim)
		for axle in axles:
			var arch: Array[Vector3] = []
			for step in 13:
				var angle := PI * float(step) / 12.0
				arch.append(Vector3(side * 1.006, 0.43 + sin(angle) * 0.43, axle + cos(angle) * 0.43))
			tube(arch, 0.027, trim)
			add_wheel(side * 0.98, 0.43, axle, 0.40, 0.245, 0.27, 7, "c1c9cc")
		box(Vector3(side * 0.68, 0.78, -2.17), Vector3(0.36, 0.09, 0.035), head)
		box(Vector3(side * 0.87, 0.69, -2.155), Vector3(0.07, 0.14, 0.035), amber)
		box(Vector3(side * 0.76, 0.91, 2.16), Vector3(0.22, 0.28, 0.035), tail)
		tube([Vector3(side * 0.60, 1.79, -0.26), Vector3(side * 0.60, 1.74, 1.34)], 0.021, alloy)
	box(Vector3(0.0, 0.47, -2.19), Vector3(0.82, 0.20, 0.045), trim)
	box(Vector3(0.0, 1.72, 1.48), Vector3(1.42, 0.045, 0.25), paint)

