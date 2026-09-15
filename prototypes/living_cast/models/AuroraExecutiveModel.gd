extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Aurora: long-wheelbase executive sedan, low decks and restrained brightwork.


func build() -> void:
	vehicle_id = "aurora_executive"
	paint = mat("paint", "35495f", 0.48, 0.24)
	var rubber := mat("rubber", "15191d", 0.0, 0.92)
	var trim := mat("trim", "252c31", 0.28, 0.42)
	var glass := mat("glass", "1e3442", 0.42, 0.13)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "dff4ff", 0.14, 0.14, 0.75)
	var tail := mat("taillight", "b8272f", 0.12, 0.20, 0.72)
	var chrome := mat("chrome", "d4d9dc", 0.86, 0.20)
	var amber := mat("amber", "e99b2d", 0.10, 0.24, 0.42)
	set_silhouette("long_low_executive_three_box", "rear_weighted_four_door")

	var axles: Array[float] = [-1.58, 1.50]
	sculpted_shell([
		Vector3(-2.62, 0.64, 0.58), Vector3(-2.38, 0.88, 0.75),
		Vector3(-1.30, 0.98, 0.84), Vector3(0.72, 0.99, 0.87),
		Vector3(2.18, 0.92, 0.78), Vector3(2.58, 0.70, 0.61),
	], axles, 0.36, 0.36, 0.052, 0.25)
	add_underbody(4.98, 1.72, 0.24)
	add_greenhouse(-0.98, 1.46, -0.43, 1.10, 0.87, 1.39, 0.91, 0.72, 2, 0.045)
	add_aero_mirrors(-0.76, 1.02, 0.93, Vector3(0.22, 0.09, 0.17))
	add_flush_handles([-0.20, 0.78], 0.995, 0.76, chrome)

	# Long hood power ridges and full-width light signatures emphasize length.
	for side in [-1.0, 1.0]:
		tube([Vector3(side * 0.37, 0.87, -2.24), Vector3(side * 0.35, 0.91, -1.10)], 0.009, trim)
		box(Vector3(side * 0.61, 0.67, -2.59), Vector3(0.48, 0.075, 0.035), head)
		box(Vector3(side * 0.86, 0.60, -2.575), Vector3(0.08, 0.13, 0.035), amber)
		box(Vector3(side * 0.60, 0.66, 2.58), Vector3(0.50, 0.075, 0.035), tail)
		box(Vector3(side * 0.985, 0.44, 0.0), Vector3(0.035, 0.055, 3.80), chrome)
		add_wheel(side * 0.96, 0.36, -1.58, 0.36, 0.235, 0.26, 10, "d7dde0")
		add_wheel(side * 0.96, 0.36, 1.50, 0.36, 0.235, 0.26, 10, "d7dde0")
	box(Vector3(0.0, 0.62, -2.615), Vector3(0.72, 0.18, 0.035), trim)
	for bar in 5:
		box(Vector3(0.0, 0.55 + bar * 0.035, -2.635), Vector3(0.66, 0.010, 0.020), chrome)
	box(Vector3(0.0, 0.69, 2.59), Vector3(0.34, 0.025, 0.040), chrome)
	for z in [-2.63, 2.63]:
		box(Vector3(0.0, 0.35, z), Vector3(1.78, 0.09, 0.11), trim)
	add_exhaust_dual(0.62, 0.29, 2.63, 0.052)

