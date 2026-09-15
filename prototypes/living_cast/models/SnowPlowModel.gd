extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Boreal plow: high forward cab, salt hopper and a wide articulated V blade.


func build() -> void:
	vehicle_id = "snow_plow_truck"
	paint = mat("paint", "e47a22", 0.28, 0.34)
	var rubber := mat("rubber", "161a1d", 0.0, 0.94)
	var trim := mat("trim", "2b3033", 0.34, 0.46)
	var glass := mat("glass", "2a4654", 0.32, 0.16)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "e9f6ff", 0.12, 0.18, 0.78)
	var tail := mat("taillight", "c9342d", 0.10, 0.22, 0.65)
	var blade := mat("plow_steel", "d79a25", 0.58, 0.34)
	var blade_edge := mat("plow_edge", "596168", 0.78, 0.28)
	var salt := mat("road_salt", "e7edf0", 0.0, 0.92)
	var amber := mat("amber_beacon", "ffb11f", 0.10, 0.12, 1.15)
	set_silhouette("forward_cab_v_plow_hopper", "single_high_cab")

	var front_axle: Array[float] = [-2.15]
	sculpted_shell([
		Vector3(-3.28, 0.76, 0.76), Vector3(-3.02, 1.08, 1.14),
		Vector3(-1.30, 1.13, 1.22), Vector3(-0.88, 0.95, 1.04),
	], front_axle, 0.46, 0.46, 0.045, 0.30)
	add_underbody(6.05, 1.90, 0.31)
	add_greenhouse(-2.98, -1.06, -2.74, -1.38, 1.20, 2.13, 1.03, 0.88, 1, 0.055)
	add_aero_mirrors(-2.65, 1.30, 1.50, Vector3(0.26, 0.34, 0.12))
	add_flush_handles([-1.73], 1.12, 1.03, trim)

	# Tapered salt hopper; it is vehicle volume, not a decorative roof prop.
	surface([Vector3(-1.03, 0.72, -0.55), Vector3(-0.74, 2.00, -0.30), Vector3(-0.74, 2.00, 2.72), Vector3(-1.03, 0.72, 2.92)], paint)
	surface([Vector3(1.03, 0.72, 2.92), Vector3(0.74, 2.00, 2.72), Vector3(0.74, 2.00, -0.30), Vector3(1.03, 0.72, -0.55)], paint)
	surface([Vector3(-1.03, 0.72, -0.55), Vector3(1.03, 0.72, -0.55), Vector3(0.74, 2.00, -0.30), Vector3(-0.74, 2.00, -0.30)], paint)
	surface([Vector3(1.03, 0.72, 2.92), Vector3(-1.03, 0.72, 2.92), Vector3(-0.74, 2.00, 2.72), Vector3(0.74, 2.00, 2.72)], paint)
	box(Vector3(0.0, 2.02, 1.20), Vector3(1.50, 0.06, 3.02), trim)
	box(Vector3(0.0, 2.06, 1.20), Vector3(1.24, 0.03, 2.76), salt)

	# Wide V blade projects ahead of the cab with real depth and braces.
	surface([
		Vector3(-1.72, 0.14, -3.72), Vector3(0.0, 0.14, -4.10),
		Vector3(0.0, 1.05, -4.10), Vector3(-1.72, 0.94, -3.72),
	], blade)
	surface([
		Vector3(0.0, 0.14, -4.10), Vector3(1.72, 0.14, -3.72),
		Vector3(1.72, 0.94, -3.72), Vector3(0.0, 1.05, -4.10),
	], blade)
	for side in [-1.0, 1.0]:
		tube([Vector3(side * 0.65, 0.52, -3.12), Vector3(side * 0.96, 0.55, -3.82)], 0.045, trim)
		box(Vector3(side * 1.24, 0.18, -3.83), Vector3(0.92, 0.11, 0.10), blade_edge)
		box(Vector3(side * 0.78, 0.86, -3.28), Vector3(0.34, 0.18, 0.045), head)
		box(Vector3(side * 0.86, 0.67, 2.93), Vector3(0.22, 0.14, 0.045), tail)

	add_lightbar(2.25, -1.82, Color("ffb11f"), Color("ffd45c"), 1.55)
	var axles: Array[float] = [-2.15, 1.60, 2.32]
	add_axles(axles, 1.04, 0.46, 0.46, 0.28, 0.27, 7, "aeb5b9")
