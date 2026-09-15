extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Nimbus: forward-cab family minivan with panoramic glass and sliding doors.


func build() -> void:
	vehicle_id = "nimbus_minivan"
	paint = mat("paint", "6d7f92", 0.32, 0.27)
	var rubber := mat("rubber", "171b1f", 0.0, 0.93)
	var trim := mat("trim", "283137", 0.24, 0.50)
	var glass := mat("glass", "1f3e50", 0.40, 0.13)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "e3f6ff", 0.10, 0.15, 0.74)
	var tail := mat("taillight", "ca3235", 0.10, 0.21, 0.70)
	var chrome := mat("chrome", "cbd4d8", 0.76, 0.25)
	set_silhouette("forward_cab_long_arch_minivan", "panoramic_three_row")

	var axles: Array[float] = [-1.55, 1.48]
	sculpted_shell([
		Vector3(-2.48, 0.55, 0.62), Vector3(-2.22, 0.88, 0.91),
		Vector3(-1.15, 0.98, 1.00), Vector3(1.32, 0.99, 1.01),
		Vector3(2.30, 0.88, 0.88), Vector3(2.48, 0.61, 0.64),
	], axles, 0.38, 0.36, 0.055, 0.27)
	add_underbody(4.72, 1.70, 0.26)
	add_greenhouse(-2.16, 2.18, -1.78, 1.90, 1.00, 1.77, 0.91, 0.75, 3, 0.075)
	add_aero_mirrors(-1.92, 1.06, 1.15, Vector3(0.22, 0.12, 0.17))
	add_flush_handles([-0.98, 0.70], 1.005, 0.85, chrome)

	# Sliding-door rails and deep side steps communicate family/MPV use.
	for side in [-1.0, 1.0]:
		tube([Vector3(side * 1.012, 0.93, -0.24), Vector3(side * 1.012, 0.93, 1.62)], 0.011, chrome)
		tube([Vector3(side * 1.012, 0.42, -0.36), Vector3(side * 1.012, 0.42, 1.72)], 0.016, trim)
		box(Vector3(side * 0.66, 0.72, -2.46), Vector3(0.38, 0.14, 0.035), head)
		box(Vector3(side * 0.82, 1.02, 2.45), Vector3(0.13, 0.48, 0.035), tail)
		add_wheel(side * 0.95, 0.38, -1.55, 0.36, 0.225, 0.23, 8, "c7d0d4")
		add_wheel(side * 0.95, 0.38, 1.48, 0.36, 0.225, 0.23, 8, "c7d0d4")
	box(Vector3(0.0, 1.80, 0.16), Vector3(1.40, 0.035, 2.80), paint)
	for z in [-2.50, 2.50]:
		box(Vector3(0.0, 0.36, z), Vector3(1.74, 0.11, 0.11), trim)

