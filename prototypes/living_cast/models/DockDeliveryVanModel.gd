extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Dockline: forward-control delivery van with a rounded cargo roof and sliding door.


func build() -> void:
	vehicle_id = "dock_delivery_van"
	paint = mat("paint", "e6e8e5", 0.18, 0.34)
	var rubber := mat("rubber", "171b1e", 0.0, 0.93)
	var trim := mat("trim", "31383c", 0.26, 0.48)
	var glass := mat("glass", "254655", 0.34, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "e7f6ff", 0.12, 0.16, 0.72)
	var tail := mat("taillight", "cc3731", 0.10, 0.22, 0.66)
	var amber := mat("amber", "f3a324", 0.12, 0.24, 0.42)
	var steel := mat("steel", "929da3", 0.72, 0.32)
	set_silhouette("forward_control_rounded_delivery", "cab_over_engine")

	var axles: Array[float] = [-1.52, 1.62]
	sculpted_shell([
		Vector3(-2.58, 0.70, 0.65), Vector3(-2.34, 0.93, 0.90),
		Vector3(-1.30, 1.00, 0.95), Vector3(1.82, 1.01, 0.93),
		Vector3(2.48, 0.91, 0.80), Vector3(2.60, 0.72, 0.65),
	], axles, 0.37, 0.38, 0.045, 0.25)
	add_underbody(4.95, 1.75, 0.25)

	# Cab windows sit almost over the front axle; cargo roof becomes a separate
	# rounded volume instead of one rectangular box from bumper to bumper.
	add_greenhouse(-2.38, -0.72, -2.17, -1.02, 0.94, 1.82, 0.95, 0.82, 1, 0.045)
	add_rounded_volume(-0.92, 2.43, 0.96, 0.93, 0.87, 1.58, 1.92, paint)
	add_aero_mirrors(-2.06, 1.13, 1.32, Vector3(0.22, 0.28, 0.12))
	add_flush_handles([-1.18, 0.42], 1.015, 0.83, trim)

	# Sliding door seam/rail and ribbed rear shutter are functional visual cues.
	for side in [-1.0, 1.0]:
		tube([Vector3(side * 1.015, 0.82, -0.32), Vector3(side * 1.015, 0.82, 1.45), Vector3(side * 1.015, 1.48, 1.45)], 0.011, trim)
		box(Vector3(side * 1.02, 1.42, 0.55), Vector3(0.025, 0.028, 1.72), steel)
		add_wheel(side * 0.98, 0.37, -1.52, 0.38, 0.23, 0.23, 6, "aab4b9")
		add_wheel(side * 0.98, 0.37, 1.62, 0.38, 0.23, 0.23, 6, "aab4b9")
		box(Vector3(side * 0.68, 0.67, -2.58), Vector3(0.30, 0.16, 0.04), head)
		box(Vector3(side * 0.91, 1.05, 2.59), Vector3(0.12, 0.58, 0.04), tail)
		box(Vector3(side * 0.94, 1.55, 2.585), Vector3(0.09, 0.08, 0.04), amber)
	for y in range(7):
		box(Vector3(0.0, 0.83 + y * 0.13, 2.61), Vector3(1.54, 0.026, 0.025), steel)
	for z in [-2.63, 2.63]:
		box(Vector3(0.0, 0.38, z), Vector3(1.88, 0.14, 0.12), trim)

